#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "tracked_window.h"

namespace cf::hyprland_clients {

/// Parses the JSON array from `hyprctl -j clients`. Returns every client; callers
/// decide what is capturable. `error` gets a message on malformed input.
bool parse_clients(const std::string& json, std::vector<TrackedWindow>& out, std::string* error = nullptr);

/// Parses the single object from `hyprctl -j activewindow`.
bool parse_client(const std::string& json, TrackedWindow& out, std::string* error = nullptr);

/// "0x55f0330b8760" -> 0x55f0330b8760; also accepts the bare hex Hyprland events use.
uint64_t parse_address(const std::string& text);

}  // namespace cf::hyprland_clients
