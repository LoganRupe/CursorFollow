#include "app.h"

#include <gtk/gtk.h>

#include "settings_window.h"

namespace cf {

namespace {

const char* kCss = R"css(
.cf-output { background-color: #000000; }
.cf-output picture { background-color: #000000; }
.cf-fallback {
  background-color: rgba(0, 0, 0, 0.74);
  color: #ffffff;
  border-radius: 12px;
  padding: 28px 36px;
}
.cf-fallback image { color: rgba(255, 255, 255, 0.82); }
.cf-fallback-title { font-size: 22px; font-weight: 600; }
.cf-fallback-message { font-size: 14px; color: rgba(255, 255, 255, 0.72); }
.cf-metrics {
  font-family: monospace;
  font-size: 11px;
  font-weight: 600;
  color: #ffffff;
  background-color: rgba(0, 0, 0, 0.55);
  border-radius: 4px;
  padding: 4px 7px;
}
.cf-caption { font-size: 11px; font-weight: 700; letter-spacing: 0.06em; opacity: 0.7; }
.cf-card { background-color: alpha(currentColor, 0.05); border: 1px solid alpha(currentColor, 0.08); border-radius: 9px; padding: 10px 12px; }
.cf-list { background: transparent; }
.cf-list row { border-radius: 6px; }
.cf-row-title { font-weight: 600; }
.cf-row-subtitle { font-size: 12px; opacity: 0.65; }
.cf-row-selected { background-color: alpha(@accent_bg_color, 0.18); }
.cf-row-dimmed .cf-row-title { opacity: 0.5; }
.cf-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;
  padding: 2px 7px;
  border-radius: 999px;
  background-color: alpha(currentColor, 0.12);
}
.cf-badge-live { background-color: #2ec27e; color: #ffffff; }
.cf-hint { font-size: 12px; opacity: 0.7; }
)css";

}  // namespace

App::App(GtkApplication* gtk_app)
    : gtk_app_(gtk_app), settings_(), tracker_(settings_), engine_(settings_) {}

App::~App() {
    engine_.stop();
    tracker_.stop();
}

void App::install_css() {
    GtkCssProvider* provider = gtk_css_provider_new();
    gtk_css_provider_load_from_string(provider, kCss);
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(provider),
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

void App::startup() {
    if (started_) return;
    started_ = true;
    install_css();

    output_ = std::make_unique<OutputWindow>(gtk_app_, settings_, ipc_);
    panel_ = std::make_unique<PanelWindow>(gtk_app_, *this);
    wire();

    if (!engine_.init(gdk_display_get_default())) {
        g_warning("Capture unavailable: %s", engine_.error().c_str());
        output_->set_capture_unavailable(engine_.error());
    }
    tracker_.start();
    tracker_.refresh();
    if (!tracker_.selected() && engine_.supported()) output_->set_no_target();

    if (!settings_.hide_when_not_sharing()) output_->show();

    if (settings_.auto_share_on_start() && engine_.supported()) {
        if (auto candidate = tracker_.pick_follow_candidate()) {
            engine_.clear_user_stopped();
            tracker_.select(*candidate);
        }
    }
    panel_->refresh();
}

void App::show_panel() {
    if (panel_) panel_->show();
}

void App::show_settings() {
    if (panel_) {
        panel_->show();
        show_settings_window(panel_->window(), *this);
    }
}

void App::wire() {
    tracker_.on_windows_changed = [this] { if (panel_) panel_->refresh(); };
    tracker_.on_mode_changed = [this] { if (panel_) panel_->refresh(); };
    tracker_.on_selection_changed = [this](const std::optional<TrackedWindow>& w) { handle_selection_changed(w); };

    engine_.on_state_changed = [this] { handle_capture_state_changed(); };
    engine_.on_error = [this](const std::string& message) {
        output_->set_target_unavailable(message);
        if (panel_) panel_->refresh();
    };
    engine_.on_frame = [this](GdkTexture* texture, int w, int h) { output_->present_frame(texture, w, h); };

    output_->on_visibility_changed = [this] { if (panel_) panel_->refresh(); };
}

void App::handle_selection_changed(const std::optional<TrackedWindow>& window) {
    if (!window) {
        if (auto msg = tracker_.target_unavailable_message()) {
            output_->set_target_unavailable(*msg);
            if (engine_.is_capturing()) engine_.stop();
        } else {
            output_->set_no_target();
        }
        if (panel_) panel_->refresh();
        return;
    }

    output_->prepare_for_capture(window->title);
    if (engine_.is_capturing()) {
        engine_.switch_target(*window);
    } else if (!engine_.user_stopped() && engine_.supported()) {
        engine_.start(*window);
    } else {
        output_->set_paused(window->title);
    }
    sync_output_for_capture();
    if (panel_) panel_->refresh();
}

void App::handle_capture_state_changed() {
    if (engine_.is_capturing()) {
        sync_output_for_capture();
    } else if (auto msg = tracker_.target_unavailable_message()) {
        output_->set_target_unavailable(*msg);
    } else if (!tracker_.selected()) {
        output_->set_no_target();
    } else if (!engine_.last_error()) {
        output_->set_paused(tracker_.selected()->title);
    }
    apply_hide_when_not_sharing();
    if (panel_) panel_->refresh();
}

void App::sync_output_for_capture() {
    if (!engine_.is_capturing() || !tracker_.selected()) return;
    output_->update_for_capture(engine_.capture_width(), engine_.capture_height(), tracker_.selected()->title);
}

void App::apply_hide_when_not_sharing() {
    if (!settings_.hide_when_not_sharing()) return;
    if (engine_.is_capturing()) output_->show(); else output_->hide();
}

void App::select_window(const TrackedWindow& window) {
    tracker_.select(window);
}

void App::toggle_filter_membership(const TrackedWindow& window) {
    tracker_.toggle_filter_membership(window);
}

void App::set_auto_follow(bool enabled) {
    tracker_.set_auto_follow_enabled(enabled);
    if (enabled && engine_.is_capturing()) {
        // Catch up with whatever is focused right now.
        if (auto active = tracker_.active_window(); active && tracker_.should_follow(*active)) {
            if (!tracker_.selected() || *tracker_.selected() != *active) tracker_.select(*active);
        }
    }
    if (panel_) panel_->refresh();
}

void App::toggle_auto_follow() {
    set_auto_follow(!tracker_.auto_follow_enabled());
}

void App::set_filter_mode(FilterMode mode) {
    tracker_.set_filter_mode(mode);
}

void App::refresh_windows() {
    tracker_.refresh();
}

void App::toggle_output() {
    output_->toggle();
}

void App::toggle_capture() {
    if (engine_.is_capturing()) pause_capture(); else resume_capture();
}

void App::pause_capture() {
    if (!engine_.is_capturing()) return;
    engine_.user_stop();
    g_message("Capture paused by user");
}

void App::resume_capture() {
    if (!engine_.supported()) return;
    engine_.clear_user_stopped();
    if (tracker_.selected()) {
        engine_.start(*tracker_.selected());
        output_->prepare_for_capture(tracker_.selected()->title);
        sync_output_for_capture();
    } else if (auto candidate = tracker_.pick_follow_candidate()) {
        tracker_.select(*candidate);  // selection handler starts capture
    } else {
        g_message("Resume ignored: no window to capture");
        output_->set_no_target();
    }
    if (panel_) panel_->refresh();
}

void App::quit() {
    engine_.stop();
    tracker_.stop();
    g_application_quit(G_APPLICATION(gtk_app_));
}

void App::set_start_on_login(bool enabled) {
    std::string err;
    if (!settings_.set_start_on_login(enabled, &err)) g_warning("Start on login: %s", err.c_str());
}

void App::set_hide_when_not_sharing(bool enabled) {
    settings_.set_hide_when_not_sharing(enabled);
    if (enabled) apply_hide_when_not_sharing(); else output_->show();
}

void App::set_pin_output_on_top(bool enabled) {
    settings_.set_pin_output_on_top(enabled);
    output_->set_pin_on_top(enabled);
}

void App::set_show_resolution(bool enabled) {
    settings_.set_show_resolution(enabled);
    output_->set_show_resolution(enabled);
}

void App::set_show_frame_count(bool enabled) {
    settings_.set_show_frame_count(enabled);
    output_->set_show_frame_count(enabled);
}

void App::set_presentation_mode(PresentationMode mode) {
    settings_.set_presentation_mode(mode);
    output_->set_presentation_mode(mode);
}

void App::set_capture_quality(CaptureQuality quality) {
    engine_.set_quality(quality);
}

}  // namespace cf
