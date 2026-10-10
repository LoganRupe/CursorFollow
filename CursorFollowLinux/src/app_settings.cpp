#include "app_settings.h"

#include <glib.h>
#include <glib/gstdio.h>

#include <fstream>
#include <vector>

namespace cf {

namespace {

constexpr const char* kGroup = "settings";
constexpr const char* kAutoShareOnStart = "autoShareOnStart";
constexpr const char* kHideWhenNotSharing = "hideWhenNotSharing";
constexpr const char* kPinOutputOnTop = "pinOutputOnTop";
constexpr const char* kShowResolution = "showResolution";
constexpr const char* kShowFrameCount = "showFrameCount";
constexpr const char* kAutoFollowEnabled = "autoFollowEnabled";
constexpr const char* kPresentationMode = "outputPresentationMode";
constexpr const char* kCaptureQuality = "captureQuality";
constexpr const char* kFilterMode = "filterMode";
constexpr const char* kExcludedApps = "excludedApps";
constexpr const char* kIncludedApps = "includedApps";

GKeyFile* kf(void* p) { return static_cast<GKeyFile*>(p); }

}  // namespace

const char* presentation_mode_name(PresentationMode mode) {
    switch (mode) {
        case PresentationMode::Fit: return "fit";
        case PresentationMode::Fill: return "fill";
        case PresentationMode::Actual: return "actualSize";
    }
    return "fit";
}

bool presentation_mode_from_name(const std::string& name, PresentationMode& out) {
    if (name == "fit") { out = PresentationMode::Fit; return true; }
    if (name == "fill") { out = PresentationMode::Fill; return true; }
    if (name == "actualSize") { out = PresentationMode::Actual; return true; }
    return false;
}

const char* capture_quality_name(CaptureQuality quality) {
    switch (quality) {
        case CaptureQuality::Balanced: return "balanced";
        case CaptureQuality::Smooth: return "smooth";
        case CaptureQuality::Efficient: return "efficient";
    }
    return "balanced";
}

bool capture_quality_from_name(const std::string& name, CaptureQuality& out) {
    if (name == "balanced") { out = CaptureQuality::Balanced; return true; }
    if (name == "smooth") { out = CaptureQuality::Smooth; return true; }
    if (name == "efficient") { out = CaptureQuality::Efficient; return true; }
    return false;
}

int capture_quality_max_fps(CaptureQuality quality) {
    switch (quality) {
        case CaptureQuality::Balanced: return 30;
        case CaptureQuality::Smooth: return 60;
        case CaptureQuality::Efficient: return 15;
    }
    return 30;
}

std::string AppSettings::default_path() {
    gchar* p = g_build_filename(g_get_user_config_dir(), "CursorFollowLinux", "settings.ini", nullptr);
    std::string s(p);
    g_free(p);
    return s;
}

std::string AppSettings::autostart_path() {
    gchar* p = g_build_filename(g_get_user_config_dir(), "autostart", "io.github.loganrupe.CursorFollowLinux.desktop", nullptr);
    std::string s(p);
    g_free(p);
    return s;
}

AppSettings::AppSettings() : AppSettings(default_path()) {}

AppSettings::AppSettings(const std::string& path) : path_(path), keyfile_(g_key_file_new()) {
    load();
}

AppSettings::~AppSettings() {
    g_key_file_free(kf(keyfile_));
}

void AppSettings::load() {
    GError* err = nullptr;
    if (!g_key_file_load_from_file(kf(keyfile_), path_.c_str(), G_KEY_FILE_KEEP_COMMENTS, &err)) {
        if (err && err->code != G_FILE_ERROR_NOENT) {
            g_warning("Settings: could not read %s: %s", path_.c_str(), err->message);
        }
        g_clear_error(&err);
        return;
    }

    auto get_bool = [&](const char* key, bool fallback) {
        GError* e = nullptr;
        gboolean v = g_key_file_get_boolean(kf(keyfile_), kGroup, key, &e);
        if (e) { g_clear_error(&e); return fallback; }
        return v != FALSE;
    };
    auto get_string = [&](const char* key) {
        gchar* v = g_key_file_get_string(kf(keyfile_), kGroup, key, nullptr);
        std::string s = v ? v : "";
        g_free(v);
        return s;
    };
    auto get_list = [&](const char* key) {
        std::set<std::string> out;
        gsize n = 0;
        gchar** v = g_key_file_get_string_list(kf(keyfile_), kGroup, key, &n, nullptr);
        for (gsize i = 0; v && i < n; ++i) {
            if (v[i] && *v[i]) out.insert(v[i]);
        }
        g_strfreev(v);
        return out;
    };

    auto_share_on_start_ = get_bool(kAutoShareOnStart, false);
    hide_when_not_sharing_ = get_bool(kHideWhenNotSharing, false);
    pin_output_on_top_ = get_bool(kPinOutputOnTop, false);
    show_resolution_ = get_bool(kShowResolution, false);
    show_frame_count_ = get_bool(kShowFrameCount, false);
    auto_follow_enabled_ = get_bool(kAutoFollowEnabled, true);
    presentation_mode_from_name(get_string(kPresentationMode), presentation_mode_);
    capture_quality_from_name(get_string(kCaptureQuality), capture_quality_);
    filter_mode_from_name(get_string(kFilterMode), filter_mode_);
    excluded_apps_ = get_list(kExcludedApps);
    included_apps_ = get_list(kIncludedApps);
}

void AppSettings::save() {
    gchar* dir = g_path_get_dirname(path_.c_str());
    g_mkdir_with_parents(dir, 0700);
    g_free(dir);
    GError* err = nullptr;
    if (!g_key_file_save_to_file(kf(keyfile_), path_.c_str(), &err)) {
        g_warning("Settings: could not write %s: %s", path_.c_str(), err ? err->message : "unknown error");
        g_clear_error(&err);
    }
}

void AppSettings::save_bool(const char* key, bool value) {
    g_key_file_set_boolean(kf(keyfile_), kGroup, key, value);
    save();
}

void AppSettings::save_string(const char* key, const std::string& value) {
    g_key_file_set_string(kf(keyfile_), kGroup, key, value.c_str());
    save();
}

void AppSettings::save_list(const char* key, const std::set<std::string>& values) {
    std::vector<const gchar*> list;
    for (const auto& v : values) list.push_back(v.c_str());
    g_key_file_set_string_list(kf(keyfile_), kGroup, key, list.data(), list.size());
    save();
}

void AppSettings::set_auto_share_on_start(bool value) { auto_share_on_start_ = value; save_bool(kAutoShareOnStart, value); }
void AppSettings::set_hide_when_not_sharing(bool value) { hide_when_not_sharing_ = value; save_bool(kHideWhenNotSharing, value); }
void AppSettings::set_pin_output_on_top(bool value) { pin_output_on_top_ = value; save_bool(kPinOutputOnTop, value); }
void AppSettings::set_show_resolution(bool value) { show_resolution_ = value; save_bool(kShowResolution, value); }
void AppSettings::set_show_frame_count(bool value) { show_frame_count_ = value; save_bool(kShowFrameCount, value); }
void AppSettings::set_auto_follow_enabled(bool value) { auto_follow_enabled_ = value; save_bool(kAutoFollowEnabled, value); }
void AppSettings::set_presentation_mode(PresentationMode mode) { presentation_mode_ = mode; save_string(kPresentationMode, presentation_mode_name(mode)); }
void AppSettings::set_capture_quality(CaptureQuality quality) { capture_quality_ = quality; save_string(kCaptureQuality, capture_quality_name(quality)); }
void AppSettings::set_filter_mode(FilterMode mode) { filter_mode_ = mode; save_string(kFilterMode, filter_mode_name(mode)); }
void AppSettings::set_excluded_apps(const std::set<std::string>& apps) { excluded_apps_ = apps; save_list(kExcludedApps, apps); }
void AppSettings::set_included_apps(const std::set<std::string>& apps) { included_apps_ = apps; save_list(kIncludedApps, apps); }

bool AppSettings::start_on_login() const {
    return g_file_test(autostart_path().c_str(), G_FILE_TEST_IS_REGULAR);
}

bool AppSettings::set_start_on_login(bool enabled, std::string* error) {
    const std::string path = autostart_path();
    if (!enabled) {
        if (g_file_test(path.c_str(), G_FILE_TEST_EXISTS) && g_unlink(path.c_str()) != 0) {
            if (error) *error = "Could not remove " + path;
            return false;
        }
        return true;
    }

    // Point the entry at this exact binary so it keeps working when cursorfollow
    // is not on PATH (for example a build-tree run).
    gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    std::string exec = exe ? exe : "cursorfollow";
    g_free(exe);

    gchar* dir = g_path_get_dirname(path.c_str());
    g_mkdir_with_parents(dir, 0700);
    g_free(dir);

    std::ofstream out(path);
    if (!out) {
        if (error) *error = "Could not write " + path;
        return false;
    }
    out << "[Desktop Entry]\n"
           "Type=Application\n"
           "Name=CursorFollow\n"
           "Comment=Share one window that follows the window you are working in\n"
           "Exec=" << exec << "\n"
           "Icon=io.github.loganrupe.CursorFollowLinux\n"
           "Terminal=false\n"
           "X-GNOME-Autostart-enabled=true\n";
    return static_cast<bool>(out);
}

}  // namespace cf
