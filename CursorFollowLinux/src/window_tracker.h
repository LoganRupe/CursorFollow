#pragma once

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "app_settings.h"
#include "hyprland_ipc.h"
#include "tracked_window.h"
#include "window_filter.h"

namespace cf {

/// Enumerates Hyprland toplevels and publishes a selectable list. When auto-follow
/// is on it switches the selection to the newly focused window, debounced so an
/// alt-tab sweep does not restart capture for every window passed over.
class WindowTracker {
public:
    explicit WindowTracker(AppSettings& settings);
    ~WindowTracker();

    WindowTracker(const WindowTracker&) = delete;
    WindowTracker& operator=(const WindowTracker&) = delete;

    /// Connects to the Hyprland event stream. Returns false (and sets error()) when
    /// this is not a Hyprland session.
    bool start();
    void stop();

    /// Re-reads `hyprctl clients`. Clears the selection (with a reason) when the
    /// selected window is gone.
    void refresh();

    const std::vector<TrackedWindow>& windows() const { return windows_; }
    const std::optional<TrackedWindow>& selected() const { return selected_; }
    const std::optional<std::string>& target_unavailable_message() const { return target_unavailable_; }
    const std::string& error() const { return error_; }

    void select(const TrackedWindow& window);

    bool auto_follow_enabled() const { return auto_follow_; }
    void set_auto_follow_enabled(bool enabled);

    FilterMode filter_mode() const { return filter_mode_; }
    void set_filter_mode(FilterMode mode);
    bool should_follow(const TrackedWindow& window) const;
    bool is_in_active_list(const TrackedWindow& window) const;
    void toggle_filter_membership(const TrackedWindow& window);

    /// The currently focused capturable window, straight from the compositor.
    std::optional<TrackedWindow> active_window();

    /// Picks the best window to start following right now: the focused one if the
    /// filter allows it, else the most recently focused allowed window.
    std::optional<TrackedWindow> pick_follow_candidate();

    /// Parses `hyprctl -j clients` output. Exposed for the tests; does not filter.
    static bool parse_clients(const std::string& json, std::vector<TrackedWindow>& out, std::string* error = nullptr);
    static bool parse_client(const std::string& json, TrackedWindow& out, std::string* error = nullptr);

    /// Fired after every successful refresh.
    std::function<void()> on_windows_changed;
    /// Fired when the selection changes (nullopt when cleared; see target_unavailable_message()).
    std::function<void(const std::optional<TrackedWindow>&)> on_selection_changed;
    /// Fired when auto-follow or filter state changes.
    std::function<void()> on_mode_changed;

private:
    void handle_event(const std::string& name, const std::string& data);
    void schedule_refresh();
    void handle_activation(uint64_t address);
    static int on_refresh_timer(void* user_data);
    static int on_follow_timer(void* user_data);
    void follow_pending();

    AppSettings& settings_;
    HyprlandIpc ipc_;
    std::vector<TrackedWindow> windows_;
    std::optional<TrackedWindow> selected_;
    std::optional<std::string> target_unavailable_;
    std::string error_;
    bool auto_follow_ = true;
    FilterMode filter_mode_ = FilterMode::All;
    FilterLists lists_;
    unsigned refresh_timer_ = 0;
    unsigned follow_timer_ = 0;
    uint64_t pending_follow_address_ = 0;
    uint64_t own_address_hint_ = 0;
};

}  // namespace cf
