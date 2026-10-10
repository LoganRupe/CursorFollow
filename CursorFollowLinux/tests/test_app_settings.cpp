#include "app_settings.h"

#include <glib.h>
#include <glib/gstdio.h>

#include "check.h"

using namespace cf;

int main() {
    gchar* dir = g_dir_make_tmp("cursorfollow-settings-XXXXXX", nullptr);
    CHECK(dir != nullptr);
    std::string path = std::string(dir) + "/nested/settings.ini";

    {
        AppSettings s(path);
        // Defaults.
        CHECK(!s.auto_share_on_start());
        CHECK(s.auto_follow_enabled());
        CHECK(s.presentation_mode() == PresentationMode::Fit);
        CHECK(s.capture_quality() == CaptureQuality::Balanced);
        CHECK(s.filter_mode() == FilterMode::All);
        CHECK(s.excluded_apps().empty());

        s.set_auto_share_on_start(true);
        s.set_hide_when_not_sharing(true);
        s.set_show_frame_count(true);
        s.set_auto_follow_enabled(false);
        s.set_presentation_mode(PresentationMode::Actual);
        s.set_capture_quality(CaptureQuality::Smooth);
        s.set_filter_mode(FilterMode::Exclude);
        s.set_excluded_apps({"slack", "teams-for-linux"});
        s.set_included_apps({"chromium"});
    }
    CHECK(g_file_test(path.c_str(), G_FILE_TEST_IS_REGULAR));
    {
        AppSettings s(path);
        CHECK(s.auto_share_on_start());
        CHECK(s.hide_when_not_sharing());
        CHECK(s.show_frame_count());
        CHECK(!s.show_resolution());
        CHECK(!s.auto_follow_enabled());
        CHECK(s.presentation_mode() == PresentationMode::Actual);
        CHECK(s.capture_quality() == CaptureQuality::Smooth);
        CHECK(s.filter_mode() == FilterMode::Exclude);
        CHECK_EQ(s.excluded_apps().size(), 2u);
        CHECK(s.excluded_apps().count("teams-for-linux") == 1);
        CHECK(s.included_apps().count("chromium") == 1);
    }

    // Unknown enum values fall back to defaults instead of failing to load.
    g_file_set_contents(path.c_str(), "[settings]\noutputPresentationMode=bogus\ncaptureQuality=nope\nfilterMode=??\n", -1, nullptr);
    {
        AppSettings s(path);
        CHECK(s.presentation_mode() == PresentationMode::Fit);
        CHECK(s.capture_quality() == CaptureQuality::Balanced);
        CHECK(s.filter_mode() == FilterMode::All);
    }

    CHECK_EQ(capture_quality_max_fps(CaptureQuality::Balanced), 30);
    CHECK_EQ(capture_quality_max_fps(CaptureQuality::Smooth), 60);
    CHECK_EQ(capture_quality_max_fps(CaptureQuality::Efficient), 15);
    PresentationMode pm;
    CHECK(presentation_mode_from_name("fill", pm) && pm == PresentationMode::Fill);
    CHECK(!presentation_mode_from_name("FILL", pm));

    g_remove(path.c_str());
    std::string nested = std::string(dir) + "/nested";
    g_rmdir(nested.c_str());
    g_rmdir(dir);
    g_free(dir);
    return check_summary("test_app_settings");
}
