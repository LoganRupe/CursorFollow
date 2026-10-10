#pragma once

#include <set>
#include <string>

#include "tracked_window.h"

namespace cf {

/// The two user-managed identity lists. Which one applies depends on FilterMode.
struct FilterLists {
    std::set<std::string> excluded;
    std::set<std::string> included;
};

/// Pure filter logic, kept free of GTK and Wayland so the tests can drive it with
/// plain TrackedWindow values. WindowTracker delegates here.
namespace window_filter {

/// Windows CursorFollow never lists or follows: its own windows.
bool is_always_excluded_app(const std::string& app_id);

/// Whether a raw Hyprland client is worth listing at all (mapped, titled, not tiny,
/// not one of ours). `reason` receives a short label when the answer is no.
bool is_capturable(const TrackedWindow& window, std::string* reason = nullptr);

/// Whether auto-follow may switch to `window` under the current mode and lists.
bool should_follow(const TrackedWindow& window, FilterMode mode, const FilterLists& lists);

/// Whether `window` is a member of the list that the current mode consults.
bool is_in_active_list(const TrackedWindow& window, FilterMode mode, const FilterLists& lists);

/// Adds or removes `window` from the list the current mode consults. No-op for All.
void toggle_membership(const TrackedWindow& window, FilterMode mode, FilterLists& lists);

}  // namespace window_filter
}  // namespace cf
