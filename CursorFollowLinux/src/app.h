#pragma once

#include <memory>
#include <string>

#include "app_settings.h"
#include "capture_engine.h"
#include "hyprland_ipc.h"
#include "output_window.h"
#include "panel_window.h"
#include "window_tracker.h"

typedef struct _GtkApplication GtkApplication;

namespace cf {

/// Wires WindowTracker, CaptureEngine and the two windows together; the Linux
/// counterpart of the macOS AppCoordinator. Owns the process lifetime.
class App {
public:
    explicit App(GtkApplication* gtk_app);
    ~App();

    App(const App&) = delete;
    App& operator=(const App&) = delete;

    /// Called once from GApplication::startup.
    void startup();
    /// Called from GApplication::activate (first launch and every plain re-launch).
    void show_panel();
    void show_settings();

    AppSettings& settings() { return settings_; }
    WindowTracker& tracker() { return tracker_; }
    const WindowTracker& tracker() const { return tracker_; }
    CaptureEngine& engine() { return engine_; }
    const CaptureEngine& engine() const { return engine_; }
    OutputWindow& output() { return *output_; }

    // Panel and CLI actions.
    void select_window(const TrackedWindow& window);
    void toggle_filter_membership(const TrackedWindow& window);
    void set_auto_follow(bool enabled);
    void toggle_auto_follow();
    void set_filter_mode(FilterMode mode);
    void refresh_windows();
    void toggle_output();
    void toggle_capture();
    void pause_capture();
    void resume_capture();
    void quit();

    // Settings that need to be applied live.
    void set_start_on_login(bool enabled);
    void set_hide_when_not_sharing(bool enabled);
    void set_pin_output_on_top(bool enabled);
    void set_show_resolution(bool enabled);
    void set_show_frame_count(bool enabled);
    void set_presentation_mode(PresentationMode mode);
    void set_capture_quality(CaptureQuality quality);

private:
    void wire();
    void handle_selection_changed(const std::optional<TrackedWindow>& window);
    void handle_capture_state_changed();
    void sync_output_for_capture();
    void apply_hide_when_not_sharing();
    void install_css();

    GtkApplication* gtk_app_ = nullptr;
    AppSettings settings_;
    HyprlandIpc ipc_;
    WindowTracker tracker_;
    CaptureEngine engine_;
    std::unique_ptr<OutputWindow> output_;
    std::unique_ptr<PanelWindow> panel_;
    bool started_ = false;
};

}  // namespace cf
