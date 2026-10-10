#include "window_filter.h"

#include "check.h"

using namespace cf;

static TrackedWindow make(const char* app, const char* title, int w = 800, int h = 600) {
    TrackedWindow win;
    win.address = 0x55f0330b8760;
    win.app_id = app;
    win.title = title;
    win.width = w;
    win.height = h;
    return win;
}

int main() {
    FilterLists lists;
    lists.excluded = {"slack"};
    lists.included = {"chromium"};

    TrackedWindow slack = make("slack", "Slack");
    TrackedWindow chromium = make("chromium", "ExpLAN - Chromium");
    TrackedWindow foot = make("foot", "~");

    // All: everything is followable and nothing is "in the list".
    CHECK(window_filter::should_follow(slack, FilterMode::All, lists));
    CHECK(!window_filter::is_in_active_list(slack, FilterMode::All, lists));

    // Exclude: listed apps are skipped, everything else follows.
    CHECK(!window_filter::should_follow(slack, FilterMode::Exclude, lists));
    CHECK(window_filter::should_follow(chromium, FilterMode::Exclude, lists));
    CHECK(window_filter::should_follow(foot, FilterMode::Exclude, lists));
    CHECK(window_filter::is_in_active_list(slack, FilterMode::Exclude, lists));

    // Include: only listed apps follow.
    CHECK(window_filter::should_follow(chromium, FilterMode::Include, lists));
    CHECK(!window_filter::should_follow(foot, FilterMode::Include, lists));
    CHECK(window_filter::is_in_active_list(chromium, FilterMode::Include, lists));

    // Toggling membership flips the list the mode consults, and only that list.
    window_filter::toggle_membership(foot, FilterMode::Exclude, lists);
    CHECK(lists.excluded.count("foot") == 1);
    CHECK(lists.included.count("foot") == 0);
    window_filter::toggle_membership(foot, FilterMode::Exclude, lists);
    CHECK(lists.excluded.count("foot") == 0);
    window_filter::toggle_membership(foot, FilterMode::All, lists);
    CHECK(lists.excluded.count("foot") == 0 && lists.included.count("foot") == 0);

    // Windows with no identity are never blocked and never listed.
    TrackedWindow anon = make("", "untitled app");
    CHECK(window_filter::should_follow(anon, FilterMode::Include, lists));
    CHECK(!window_filter::is_in_active_list(anon, FilterMode::Exclude, lists));

    // Capturability: our own windows, untitled, tiny, unmapped and hidden are out.
    std::string reason;
    CHECK(window_filter::is_capturable(chromium));
    TrackedWindow own = make(kAppId, "CursorFollow");
    CHECK(!window_filter::is_capturable(own, &reason));
    CHECK_EQ(reason, "own window");
    TrackedWindow output = make("something-else", kOutputWindowTitle);
    CHECK(!window_filter::is_capturable(output, &reason));
    CHECK_EQ(reason, "output window");
    CHECK(!window_filter::is_capturable(make("foot", ""), &reason));
    CHECK_EQ(reason, "untitled");
    CHECK(!window_filter::is_capturable(make("foot", "tiny", 50, 50), &reason));
    CHECK_EQ(reason, "too small");
    TrackedWindow unmapped = make("foot", "x");
    unmapped.mapped = false;
    CHECK(!window_filter::is_capturable(unmapped, &reason));
    CHECK_EQ(reason, "unmapped");
    TrackedWindow hidden = make("foot", "x");
    hidden.hidden = true;
    CHECK(!window_filter::is_capturable(hidden, &reason));
    CHECK_EQ(reason, "hidden");
    TrackedWindow no_address = make("foot", "x");
    no_address.address = 0;
    CHECK(!window_filter::is_capturable(no_address, &reason));

    return check_summary("test_window_filter");
}
