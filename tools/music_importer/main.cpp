// One import per process makes cancellation independent of the game and its audio thread.
#include "audio_import.h"
#include <fstream>
#include <iostream>
#include <map>

namespace music {
json identity() {
    return {{"formatVersion", 1}, {"converter", "realmz-music-1:" MUSIC_SOURCE_ID}};
}
}

static void write_result(const music::fs::path &path, const music::json &result) {
    const auto temporary = music::fs::path(path).concat(".tmp");
    if (music::fs::exists(path) || music::fs::exists(temporary))
        throw std::runtime_error("The import result already exists.");
    std::ofstream file(temporary, std::ios::binary);
    file.exceptions(std::ios::badbit | std::ios::failbit);
    file << result.dump(2);
    file.close();
    music::fs::rename(temporary, path);
}

static int run(const std::vector<std::string> &arguments) {
    if (arguments.size() == 1 && arguments[0] == "--version") {
        std::cout << music::identity().dump() << '\n';
        return 0;
    }
    std::map<std::string, std::string> options;
    if (arguments.size() != 8) return 2;
    for (size_t i = 0; i < arguments.size(); i += 2) {
        if (!options.emplace(arguments[i], arguments[i + 1]).second) return 2;
    }
    for (const auto *key : {"--input", "--output", "--name", "--result"})
        if (!options.count(key)) return 2;
    const auto input = music::fs::u8path(options["--input"]);
    const auto output = music::fs::u8path(options["--output"]);
    const auto result_path = music::fs::u8path(options["--result"]);
    auto result = music::identity();
    try {
        if (!input.is_absolute() || !output.is_absolute() || !result_path.is_absolute())
            throw std::runtime_error("Import paths must be absolute.");
        if (!music::fs::is_regular_file(input) || music::fs::file_size(input) == 0 ||
            music::fs::file_size(input) > music::max_input_bytes)
            throw std::runtime_error("Choose a nonempty music file no larger than 256 MiB.");
        if (!music::fs::is_directory(output) || !music::fs::is_empty(output))
            throw std::runtime_error("Audio output requires a new empty staging directory.");
        result["tracks"] = music::import_audio(input, output, options["--name"]);
        result["ok"] = true;
    } catch (const std::exception &error) {
        result["ok"] = false;
        result["error"] = error.what();
    }
    try { write_result(result_path, result); }
    catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 3; }
    return result.value("ok", false) ? 0 : 1;
}

#ifdef _WIN32
#include <windows.h>
static std::string utf8(const wchar_t *value) {
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) throw std::runtime_error("Invalid Unicode argument.");
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result.data(), size, nullptr, nullptr);
    result.pop_back();
    return result;
}
int wmain(int argc, wchar_t **argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.push_back(utf8(argv[i]));
    return run(args);
}
#else
int main(int argc, char **argv) { return run({argv + 1, argv + argc}); }
#endif
