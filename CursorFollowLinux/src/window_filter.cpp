#include "window_filter.h"

namespace cf::window_filter {

namespace {
constexpr int kMinimumWindowSize = 100;  // matches the macOS tracker's tiny-window cutoff
}

bool is_always_excluded_app(const std::string& app_id) {
    return app_id == kAppId;
}

bool is_capturable(const TrackedWindow& window, std::string* reason) {
    auto fail = [&](const char* why) {
        if (reason) *reason = why;
        return false;
    };
    if (window.address == 0) return fail("no address");
    if (is_always_excluded_app(window.app_id)) return fail("own window");
    if (window.title == kOutputWindowTitle) return fail("output window");
    if (!window.mapped) return fail("unmapped");
    if (window.hidden) return fail("hidden");
    if (window.title.empty()) return fail("untitled");
    if (window.width < kMinimumWindowSize || window.height < kMinimumWindowSize) return fail("too small");
    return true;
}

bool should_follow(const TrackedWindow& window, FilterMode mode, const FilterLists& lists) {
    const std::string& id = window.identity();
    if (id.empty()) return true;
    switch (mode) {
        case FilterMode::All: return true;
        case FilterMode::Exclude: return lists.excluded.count(id) == 0;
        case FilterMode::Include: return lists.included.count(id) != 0;
    }
    return true;
}

bool is_in_active_list(const TrackedWindow& window, FilterMode mode, const FilterLists& lists) {
    const std::string& id = window.identity();
    if (id.empty()) return false;
    switch (mode) {
        case FilterMode::All: return false;
        case FilterMode::Exclude: return lists.excluded.count(id) != 0;
        case FilterMode::Include: return lists.included.count(id) != 0;
    }
    return false;
}

void toggle_membership(const TrackedWindow& window, FilterMode mode, FilterLists& lists) {
    const std::string& id = window.identity();
    if (id.empty()) return;
    std::set<std::string>* target = nullptr;
    switch (mode) {
        case FilterMode::All: return;
        case FilterMode::Exclude: target = &lists.excluded; break;
        case FilterMode::Include: target = &lists.included; break;
    }
    if (!target->erase(id)) target->insert(id);
}

}  // namespace cf::window_filter
