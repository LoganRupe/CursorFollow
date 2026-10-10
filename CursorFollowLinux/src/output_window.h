#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>

#include "app_settings.h"
#include "hyprland_ipc.h"

typedef struct _GtkApplication GtkApplication;
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkWidget GtkWidget;
typedef struct _GdkTexture GdkTexture;

namespace cf {

enum class OutputState { NoTarget, CaptureUnavailable, Paused, TargetUnavailable, WaitingForFrames, Live };

/// The stable, shareable "CursorFollow Output" window. Meeting apps pick this one
/// window in their share picker; everything else in the app exists to keep it
/// pointed at the right target.
class OutputWindow {
public:
    OutputWindow(GtkApplication* app, AppSettings& settings, HyprlandIpc& ipc);
    ~OutputWindow();

    OutputWindow(const OutputWindow&) = delete;
    OutputWindow& operator=(const OutputWindow&) = delete;

    void show();
    void hide();
    void toggle();
    bool is_visible() const { return visible_; }
    GtkWindow* window() const { return window_; }

    OutputState state() const { return state_; }
    void set_no_target();
    void set_capture_unavailable(const std::string& message);
    void set_paused(const std::optional<std::string>& target_title = std::nullopt);
    void set_target_unavailable(const std::string& message);
    void prepare_for_capture(const std::string& target_title);
    void update_for_capture(int width, int height, const std::string& target_title);

    /// Displays a captured frame; flips the state to Live on the first one.
    void present_frame(GdkTexture* texture, int width, int height);

    void set_presentation_mode(PresentationMode mode);
    void set_show_resolution(bool show);
    void set_show_frame_count(bool show);
    void set_pin_on_top(bool pin);

    double current_fps() const { return current_fps_; }

    std::function<void()> on_visibility_changed;

private:
    void build();
    void apply_state();
    void apply_presentation_mode();
    void update_metrics();
    void resize_to_actual_size();
    void apply_pin();
    static int on_fps_tick(void* user_data);
    static int on_close_request(GtkWindow* window, void* user_data);
    static void on_map(GtkWidget* widget, void* user_data);

    AppSettings& settings_;
    HyprlandIpc& ipc_;
    GtkApplication* app_ = nullptr;
    GtkWindow* window_ = nullptr;
    GtkWidget* picture_ = nullptr;
    GtkWidget* metrics_label_ = nullptr;
    GtkWidget* fallback_box_ = nullptr;
    GtkWidget* fallback_icon_ = nullptr;
    GtkWidget* fallback_title_ = nullptr;
    GtkWidget* fallback_message_ = nullptr;

    OutputState state_ = OutputState::NoTarget;
    std::string state_detail_;
    std::string target_title_;
    PresentationMode presentation_mode_ = PresentationMode::Fit;
    bool show_resolution_ = false;
    bool show_frame_count_ = false;
    bool pin_on_top_ = false;
    bool pin_applied_ = false;
    bool visible_ = false;
    int capture_width_ = 0;
    int capture_height_ = 0;
    uint64_t fps_frames_ = 0;
    double current_fps_ = 0;
    unsigned fps_timer_ = 0;
};

}  // namespace cf
