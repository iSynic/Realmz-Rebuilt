// Finite offline decoding; no application or playback state enters this process.
#pragma once
#include <filesystem>
#include <nlohmann/json.hpp>

namespace music {
using json = nlohmann::json;
namespace fs = std::filesystem;
constexpr std::uintmax_t max_input_bytes = 256ULL * 1024 * 1024;
constexpr double max_audio_seconds = 7200.0;
constexpr double max_module_seconds = 1800.0;
constexpr int max_subsongs = 32;
json import_audio(const fs::path &input, const fs::path &output, const std::string &name);
json identity();
}
