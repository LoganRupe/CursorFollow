#pragma once

#include <set>
#include <string>

#include "tracked_window.h"

namespace cf {

enum class PresentationMode { Fit, Fill, Actual };
enum class CaptureQuality { Balanced, Smooth, Efficient };

const char* presentation_mode_name(PresentationMode mode);
bool presentation_mode_from_name(const std::string& name, PresentationMode& out);
const char* capture_quality_name(CaptureQuality quality);
bool capture_quality_from_name(const std::string& name, CaptureQuality& out);
/// Frame-rate ceiling each quality preset asks the compositor for.
int capture_quality_max_fps(CaptureQuality quality);

/// User settings persisted as a GLib key file at
/// `$XDG_CONFIG_HOME/CursorFollowLinux/settings.ini`. Every setter writes through.
/// Keys mirror the macOS and Windows ports so the docs can describe one set of knobs.
class AppSettings {
public:
    AppSettings();
    explicit AppSettings(const std::string& path);  // tests point this at a temp file
    ~AppSettings();

    AppSettings(const AppSettings&) = delete;
    AppSettings& operator=(const AppSettings&) = delete;

    const std::string& path() const { return path_; }

    bool auto_share_on_start() const { return auto_share_on_start_; }
    bool hide_when_not_sharing() const { return hide_when_not_sharing_; }
    bool pin_output_on_top() const { return pin_output_on_top_; }
    bool show_resolution() const { return show_resolution_; }
    bool show_frame_count() const { return show_frame_count_; }
    bool auto_follow_enabled() const { return auto_follow_enabled_; }
    PresentationMode presentation_mode() const { return presentation_mode_; }
    CaptureQuality capture_quality() const { return capture_quality_; }
    FilterMode filter_mode() const { return filter_mode_; }
    const std::set<std::string>& excluded_apps() const { return excluded_apps_; }
    const std::set<std::string>& included_apps() const { return included_apps_; }

    void set_auto_share_on_start(bool value);
    void set_hide_when_not_sharing(bool value);
    void set_pin_output_on_top(bool value);
    void set_show_resolution(bool value);
    void set_show_frame_count(bool value);
    void set_auto_follow_enabled(bool value);
    void set_presentation_mode(PresentationMode mode);
    void set_capture_quality(CaptureQuality quality);
    void set_filter_mode(FilterMode mode);
    void set_excluded_apps(const std::set<std::string>& apps);
    void set_included_apps(const std::set<std::string>& apps);

    /// Start on login is not stored in the key file: it is the presence of an XDG
    /// autostart entry, so other tools (and the user) see the same truth.
    bool start_on_login() const;
    bool set_start_on_login(bool enabled, std::string* error = nullptr);

    static std::string default_path();
    static std::string autostart_path();

private:
    void load();
    void save();
    void save_bool(const char* key, bool value);
    void save_string(const char* key, const std::string& value);
    void save_list(const char* key, const std::set<std::string>& values);

    std::string path_;
    void* keyfile_ = nullptr;  // GKeyFile*, hidden to keep GLib out of the header

    bool auto_share_on_start_ = false;
    bool hide_when_not_sharing_ = false;
    bool pin_output_on_top_ = false;
    bool show_resolution_ = false;
    bool show_frame_count_ = false;
    bool auto_follow_enabled_ = true;
    PresentationMode presentation_mode_ = PresentationMode::Fit;
    CaptureQuality capture_quality_ = CaptureQuality::Balanced;
    FilterMode filter_mode_ = FilterMode::All;
    std::set<std::string> excluded_apps_;
    std::set<std::string> included_apps_;
};

}  // namespace cf
