#pragma once

#include <cstdint>
#include <string>

namespace cf {

/// Wayland app_id GTK assigns from the GApplication id. Hyprland reports it as the
/// window "class"; the tracker uses it to skip CursorFollow's own windows.
inline constexpr const char* kAppId = "io.github.loganrupe.CursorFollowLinux";

/// Title of the shareable output window. Must match on both the tracker (which hides
/// it from the list) and the output window (which sets it), same as the other ports.
inline constexpr const char* kOutputWindowTitle = "CursorFollow Output";

/// A capturable toplevel as reported by Hyprland (`hyprctl clients -j`).
struct TrackedWindow {
    uint64_t address = 0;      // Hyprland window address; also the capture handle
    std::string title;
    std::string app_id;        // Hyprland "class" (Wayland app_id); the filter identity
    std::string initial_title;
    int pid = 0;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    int workspace_id = 0;
    std::string workspace_name;
    int monitor = -1;
    bool floating = false;
    bool pinned = false;
    bool mapped = true;
    bool hidden = false;
    int fullscreen = 0;
    int focus_history_id = -1;

    /// Stable identity for the Include/Exclude lists (the bundle ID equivalent).
    const std::string& identity() const { return app_id; }

    /// Lower 32 bits of the address, which is what hyprland_toplevel_export_v1 wants.
    uint32_t export_handle() const { return static_cast<uint32_t>(address & 0xFFFFFFFFu); }

    std::string address_hex() const;
    std::string size_label() const;

    bool operator==(const TrackedWindow& other) const { return address == other.address; }
    bool operator!=(const TrackedWindow& other) const { return !(*this == other); }
};

enum class FilterMode { All, Exclude, Include };

const char* filter_mode_name(FilterMode mode);
bool filter_mode_from_name(const std::string& name, FilterMode& out);

}  // namespace cf
