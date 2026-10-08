// Decode supported file contents once, retaining a finite portable playback asset.
#include "audio_import.h"
#include <libopenmpt/libopenmpt.hpp>
#include <sndfile.h>
#include <array>
#include <chrono>
#include <cmath>
#include <fstream>
#include <memory>
#include <sstream>
#include <stdexcept>

namespace music {
using SoundFile = std::unique_ptr<SNDFILE, decltype(&sf_close)>;

static void validate_container_size(const fs::path &input) {
    std::ifstream file(input, std::ios::binary);
    std::array<unsigned char, 12> header{};
    if (!file.read(reinterpret_cast<char *>(header.data()), header.size())) return;
    const std::string magic(reinterpret_cast<char *>(header.data()), 4);
    if (magic != "RIFF" && magic != "RIFX" && magic != "FORM") return;
    std::uint64_t declared = 0;
    for (int i = 0; i < 4; ++i)
        declared = (declared << 8) | header[magic == "RIFF" ? 7 - i : 4 + i];
    if (declared < 4 || declared + 8 > fs::file_size(input))
        throw std::runtime_error("The audio container is truncated or damaged.");
}

static SNDFILE *open_sound(const fs::path &path, int mode, SF_INFO *info) {
#ifdef _WIN32
    return sf_wchar_open(path.c_str(), mode, info);
#else
    return sf_open(path.c_str(), mode, info);
#endif
}

class Budget {
    std::chrono::steady_clock::time_point started = std::chrono::steady_clock::now();
    double rendered = 0;
public:
    void check(double seconds, const fs::path &output = {}) {
        rendered += seconds;
        if (rendered > max_audio_seconds)
            throw std::runtime_error("An import may contain at most two hours of audio.");
        if (std::chrono::steady_clock::now() - started > std::chrono::seconds(110))
            throw std::runtime_error("Audio conversion exceeded its time limit.");
        if (!output.empty() && fs::exists(output) && fs::file_size(output) > max_input_bytes)
            throw std::runtime_error("Converted audio exceeds the 256 MiB limit.");
    }
};

class VorbisWriter {
    SoundFile file{nullptr, &sf_close};
public:
    VorbisWriter(const fs::path &path, int rate, int channels) {
        SF_INFO info{};
        info.samplerate = rate;
        info.channels = channels;
        info.format = SF_FORMAT_OGG | SF_FORMAT_VORBIS;
        file.reset(open_sound(path, SFM_WRITE, &info));
        if (!file) throw std::runtime_error("Could not create the converted audio file.");
        double quality = 0.6;
        if (!sf_command(file.get(), SFC_SET_VBR_ENCODING_QUALITY, &quality, sizeof(quality)))
            throw std::runtime_error("Vorbis quality configuration failed.");
    }
    void write(const float *data, sf_count_t frames, int channels) {
        for (sf_count_t i = 0; i < frames * channels; ++i)
            if (!std::isfinite(data[i])) throw std::runtime_error("The decoded audio contains invalid samples.");
        if (sf_writef_float(file.get(), data, frames) != frames || sf_error(file.get()))
            throw std::runtime_error("Could not write converted audio; check available disk space.");
    }
    void close() {
        sf_write_sync(file.get());
        const int error = sf_close(file.release());
        if (error) throw std::runtime_error("Could not finish the converted audio file.");
    }
};

static json import_sampled(SNDFILE *source, const SF_INFO &info, const fs::path &output,
                           const std::string &fallback, Budget &budget) {
    const int type = info.format & SF_FORMAT_TYPEMASK;
    const int subtype = info.format & SF_FORMAT_SUBMASK;
    std::string format;
    if (type == SF_FORMAT_WAV || type == SF_FORMAT_WAVEX) format = "wav";
    if (type == SF_FORMAT_AIFF) format = "aiff";
    if (type == SF_FORMAT_FLAC) format = "flac";
    if (type == SF_FORMAT_OGG && subtype == SF_FORMAT_VORBIS) format = "ogg";
    if (type == SF_FORMAT_MPEG && subtype == SF_FORMAT_MPEG_LAYER_III) format = "mp3";
    if (format.empty()) throw std::runtime_error("This audio encoding is not supported. Choose MP3, Vorbis, WAV, FLAC, or AIFF.");
    if (info.channels < 1 || info.channels > 2 || info.samplerate < 8000 || info.samplerate > 192000)
        throw std::runtime_error("Music must be mono or stereo, between 8 and 192 kHz.");
    if (info.frames <= 0 || static_cast<double>(info.frames) / info.samplerate > max_audio_seconds)
        throw std::runtime_error("Music must contain no more than two hours of audio.");
    const bool direct = format == "mp3" || format == "ogg";
    const auto path = output / "track-0.ogg";
    std::unique_ptr<VorbisWriter> writer;
    if (!direct) writer = std::make_unique<VorbisWriter>(path, info.samplerate, info.channels);
    std::array<float, 8192> samples{};
    sf_count_t total = 0;
    while (const sf_count_t frames = sf_readf_float(source, samples.data(), 4096)) {
        budget.check(static_cast<double>(frames) / info.samplerate, direct ? fs::path{} : path);
        for (sf_count_t i = 0; i < frames * info.channels; ++i)
            if (!std::isfinite(samples[static_cast<size_t>(i)])) throw std::runtime_error("Invalid decoded audio samples.");
        if (writer) writer->write(samples.data(), frames, info.channels);
        total += frames;
    }
    if (sf_error(source) || total == 0 || total != info.frames)
        throw std::runtime_error("The audio file is damaged or incomplete.");
    if (writer) writer->close();
    const char *title = sf_get_string(source, SF_STR_TITLE);
    return json::array({{{"subsong", 0}, {"title", title && *title ? std::string(title) : fallback},
        {"format", format}, {"playbackFormat", direct ? format : "ogg"},
        {"duration", static_cast<double>(total) / info.samplerate}, {"cacheFile", direct ? "" : "track-0.ogg"}}});
}

static json import_module(const fs::path &input, const fs::path &output, const std::string &fallback, Budget &budget) {
    std::ifstream stream(input, std::ios::binary);
    std::ostringstream decoder_log;
    openmpt::module module(stream, decoder_log);
    const auto format = module.get_metadata("type");
    if (format != "mod" && format != "xm" && format != "s3m" && format != "it")
        throw std::runtime_error("This tracker format is not supported. Choose MOD, XM, S3M, or IT.");
    const int count = module.get_num_subsongs();
    if (count < 1 || count > max_subsongs) throw std::runtime_error("A module may contain at most 32 subsongs.");
    module.set_repeat_count(0);
    const auto names = module.get_subsong_names();
    const auto module_title = module.get_metadata("title");
    json tracks = json::array();
    std::array<float, 8192> samples{};
    for (int song = 0; song < count; ++song) {
        module.select_subsong(song);
        module.set_position_seconds(0);
        const double expected = module.get_duration_seconds();
        if (!std::isfinite(expected) || expected <= 0 || expected > max_module_seconds)
            throw std::runtime_error("Each tracker subsong must finish within 30 minutes.");
        const std::string filename = "track-" + std::to_string(song) + ".ogg";
        const auto path = output / filename;
        VorbisWriter writer(path, 48000, 2);
        std::uint64_t total = 0;
        while (const size_t frames = module.read_interleaved_stereo(48000, 4096, samples.data())) {
            total += frames;
            if (static_cast<double>(total) / 48000 > max_module_seconds)
                throw std::runtime_error("The tracker did not reach a finite ending.");
            budget.check(static_cast<double>(frames) / 48000, path);
            writer.write(samples.data(), static_cast<sf_count_t>(frames), 2);
        }
        if (total == 0) throw std::runtime_error("The tracker contains no playable audio.");
        writer.close();
        std::string title = module_title.empty() ? fallback : module_title;
        if (count > 1) title += " — " + (names[static_cast<size_t>(song)].empty() ? "Subsong " + std::to_string(song + 1) : names[static_cast<size_t>(song)]);
        tracks.push_back({{"subsong", song}, {"title", title}, {"format", format},
            {"playbackFormat", "ogg"}, {"duration", static_cast<double>(total) / 48000}, {"cacheFile", filename}});
    }
    return tracks;
}

json import_audio(const fs::path &input, const fs::path &output, const std::string &name) {
    validate_container_size(input);
    std::ifstream signature_file(input, std::ios::binary);
    std::array<char, 4> signature{};
    signature_file.read(signature.data(), 4);
    if (std::string(signature.data(), 3) == "MAD")
        throw std::runtime_error("MAD music is not supported in this version.");
    SF_INFO info{};
    SoundFile sampled(open_sound(input, SFM_READ, &info), &sf_close);
    Budget budget;
    if (sampled) return import_sampled(sampled.get(), info, output, name, budget);
    return import_module(input, output, name, budget);
}
}
