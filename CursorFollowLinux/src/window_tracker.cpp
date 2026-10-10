#include "window_tracker.h"
#include "hyprland_clients.h"

#include <glib.h>

#include <unistd.h>

#include <algorithm>
#include <cstdlib>

namespace cf {

namespace {

constexpr unsigned kRefreshCoalesceMs = 120;
constexpr unsigned kFollowDebounceMs = 150;  // same as the macOS switchDebounceInterval

}  // namespace

WindowTracker::WindowTracker(AppSettings& settings) : settings_(settings) {
    auto_follow_ = settings_.auto_follow_enabled();
    filter_mode_ = settings_.filter_mode();
    lists_.excluded = settings_.excluded_apps();
    lists_.included = settings_.included_apps();
}

WindowTracker::~WindowTracker() {
    stop();
}

bool WindowTracker::parse_clients(const std::string& json, std::vector<TrackedWindow>& out, std::string* error) {
    return hyprland_clients::parse_clients(json, out, error);
}

bool WindowTracker::parse_client(const std::string& json, TrackedWindow& out, std::string* error) {
    return hyprland_clients::parse_client(json, out, error);
}

bool WindowTracker::start() {
    if (!HyprlandIpc::available()) {
        error_ = "Hyprland IPC socket not found. CursorFollow for Linux currently needs a Hyprland session.";
        g_warning("%s", error_.c_str());
        return false;
    }
    error_.clear();
    ipc_.start_events([this](const std::string& name, const std::string& data) { handle_event(name, data); });
    return true;
}

void WindowTracker::stop() {
    ipc_.stop_events();
    if (refresh_timer_) { g_source_remove(refresh_timer_); refresh_timer_ = 0; }
    if (follow_timer_) { g_source_remove(follow_timer_); follow_timer_ = 0; }
}

void WindowTracker::refresh() {
    std::string err;
    auto reply = ipc_.request("j/clients", &err);
    if (!reply) {
        error_ = "Could not list windows: " + err;
        g_warning("%s", error_.c_str());
        windows_.clear();
        if (on_windows_changed) on_windows_changed();
        return;
    }

    std::vector<TrackedWindow> all;
    if (!parse_clients(*reply, all, &err)) {
        error_ = "Could not parse window list: " + err;
        g_warning("%s", error_.c_str());
        return;
    }
    error_.clear();

    std::vector<TrackedWindow> shown;
    int omitted = 0;
    const int own_pid = static_cast<int>(getpid());
    for (auto& w : all) {
        std::string reason;
        if (w.pid == own_pid) {
            ++omitted;
            continue;  // belt and braces next to the app_id check: never list our own windows
        }
        if (window_filter::is_capturable(w, &reason)) {
            shown.push_back(std::move(w));
        } else {
            ++omitted;
            g_debug("Window list: skipped %s '%s' (%s)", w.app_id.c_str(), w.title.c_str(), reason.c_str());
        }
    }
    // Most recently focused first, like the macOS front-to-back CGWindowList order.
    std::stable_sort(shown.begin(), shown.end(), [](const TrackedWindow& a, const TrackedWindow& b) {
        int fa = a.focus_history_id < 0 ? 1 << 20 : a.focus_history_id;
        int fb = b.focus_history_id < 0 ? 1 << 20 : b.focus_history_id;
        return fa < fb;
    });
    windows_ = std::move(shown);
    g_message("Window list refreshed: %zu shown, %d hidden or filtered", windows_.size(), omitted);

    if (selected_) {
        auto it = std::find(windows_.begin(), windows_.end(), *selected_);
        if (it == windows_.end()) {
            g_warning("Selected window '%s' is no longer available", selected_->title.c_str());
            target_unavailable_ = selected_->title + " closed or is no longer capturable.";
            selected_.reset();
            if (on_windows_changed) on_windows_changed();
            if (on_selection_changed) on_selection_changed(selected_);
            return;
        }
        *selected_ = *it;  // keep title and geometry fresh
        target_unavailable_.reset();
    }
    if (on_windows_changed) on_windows_changed();
}

void WindowTracker::select(const TrackedWindow& window) {
    target_unavailable_.reset();
    selected_ = window;
    g_message("Selected window '%s' (%s, %s)", window.title.c_str(), window.app_id.c_str(), window.address_hex().c_str());
    if (on_selection_changed) on_selection_changed(selected_);
}

void WindowTracker::set_auto_follow_enabled(bool enabled) {
    if (auto_follow_ == enabled) return;
    auto_follow_ = enabled;
    settings_.set_auto_follow_enabled(enabled);
    g_message("Auto-follow %s", enabled ? "enabled" : "disabled");
    if (on_mode_changed) on_mode_changed();
}

void WindowTracker::set_filter_mode(FilterMode mode) {
    if (filter_mode_ == mode) return;
    filter_mode_ = mode;
    settings_.set_filter_mode(mode);
    if (on_mode_changed) on_mode_changed();
}

bool WindowTracker::should_follow(const TrackedWindow& window) const {
    return window_filter::should_follow(window, filter_mode_, lists_);
}

bool WindowTracker::is_in_active_list(const TrackedWindow& window) const {
    return window_filter::is_in_active_list(window, filter_mode_, lists_);
}

void WindowTracker::toggle_filter_membership(const TrackedWindow& window) {
    window_filter::toggle_membership(window, filter_mode_, lists_);
    if (filter_mode_ == FilterMode::Exclude) settings_.set_excluded_apps(lists_.excluded);
    if (filter_mode_ == FilterMode::Include) settings_.set_included_apps(lists_.included);
    if (on_mode_changed) on_mode_changed();
}

std::optional<TrackedWindow> WindowTracker::active_window() {
    auto reply = ipc_.request("j/activewindow");
    if (!reply) return std::nullopt;
    TrackedWindow w;
    if (!parse_client(*reply, w) || !window_filter::is_capturable(w)) return std::nullopt;
    return w;
}

std::optional<TrackedWindow> WindowTracker::pick_follow_candidate() {
    if (auto active = active_window(); active && should_follow(*active)) return active;
    for (const auto& w : windows_) {
        if (should_follow(w)) return w;
    }
    return std::nullopt;
}

void WindowTracker::handle_event(const std::string& name, const std::string& data) {
    if (name == "activewindowv2") {
        if (data.empty() || data == ",") return;
        handle_activation(hyprland_clients::parse_address(data));
        return;
    }
    static const char* const kRefreshEvents[] = {
        "openwindow", "closewindow", "windowtitlev2", "movewindowv2", "changefloatingmode",
        "fullscreen", "minimized", "workspacev2", "focusedmonv2", "pin",
    };
    for (const char* ev : kRefreshEvents) {
        if (name == ev) {
            schedule_refresh();
            return;
        }
    }
}

void WindowTracker::schedule_refresh() {
    if (refresh_timer_) return;
    refresh_timer_ = g_timeout_add(kRefreshCoalesceMs, &WindowTracker::on_refresh_timer, this);
}

int WindowTracker::on_refresh_timer(void* user_data) {
    auto* self = static_cast<WindowTracker*>(user_data);
    self->refresh_timer_ = 0;
    self->refresh();
    return G_SOURCE_REMOVE;
}

void WindowTracker::handle_activation(uint64_t address) {
    if (!auto_follow_ || address == 0) return;
    if (selected_ && selected_->address == address) return;
    pending_follow_address_ = address;
    if (follow_timer_) g_source_remove(follow_timer_);
    follow_timer_ = g_timeout_add(kFollowDebounceMs, &WindowTracker::on_follow_timer, this);
}

int WindowTracker::on_follow_timer(void* user_data) {
    auto* self = static_cast<WindowTracker*>(user_data);
    self->follow_timer_ = 0;
    self->follow_pending();
    return G_SOURCE_REMOVE;
}

void WindowTracker::follow_pending() {
    const uint64_t address = pending_follow_address_;
    pending_follow_address_ = 0;
    if (!auto_follow_ || address == 0) return;

    // Confirm the focus settled on this window rather than passing through it.
    auto active = active_window();
    if (!active || active->address != address) {
        g_debug("Auto-follow: focus moved on before the debounce elapsed");
        return;
    }
    refresh();
    auto it = std::find_if(windows_.begin(), windows_.end(), [&](const TrackedWindow& w) { return w.address == address; });
    if (it == windows_.end()) return;
    if (selected_ && *selected_ == *it) return;
    if (!should_follow(*it)) {
        g_debug("Auto-follow: '%s' blocked by %s filter", it->title.c_str(), filter_mode_name(filter_mode_));
        return;
    }
    select(*it);
}

}  // namespace cf
