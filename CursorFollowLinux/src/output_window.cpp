#include "output_window.h"

#include <gtk/gtk.h>

#include <cstdio>

#include "hyprland_clients.h"
#include "tracked_window.h"

namespace cf {

OutputWindow::OutputWindow(GtkApplication* app, AppSettings& settings, HyprlandIpc& ipc)
    : settings_(settings), ipc_(ipc), app_(app) {
    presentation_mode_ = settings.presentation_mode();
    show_resolution_ = settings.show_resolution();
    show_frame_count_ = settings.show_frame_count();
    pin_on_top_ = settings.pin_output_on_top();
    build();
}

OutputWindow::~OutputWindow() {
    if (fps_timer_) g_source_remove(fps_timer_);
    if (window_) gtk_window_destroy(window_);
}

void OutputWindow::build() {
    window_ = GTK_WINDOW(gtk_application_window_new(app_));
    gtk_window_set_title(window_, kOutputWindowTitle);
    gtk_window_set_default_size(window_, 960, 540);
    gtk_window_set_hide_on_close(window_, TRUE);
    gtk_widget_add_css_class(GTK_WIDGET(window_), "cf-output");
    g_signal_connect(window_, "close-request", G_CALLBACK(&OutputWindow::on_close_request), this);
    g_signal_connect(window_, "map", G_CALLBACK(&OutputWindow::on_map), this);

    GtkWidget* overlay = gtk_overlay_new();
    gtk_window_set_child(window_, overlay);

    picture_ = gtk_picture_new();
    gtk_picture_set_can_shrink(GTK_PICTURE(picture_), TRUE);
    gtk_widget_set_hexpand(picture_, TRUE);
    gtk_widget_set_vexpand(picture_, TRUE);
    gtk_overlay_set_child(GTK_OVERLAY(overlay), picture_);

    // Fallback card (no target / paused / unavailable), centred over the picture.
    fallback_box_ = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_add_css_class(fallback_box_, "cf-fallback");
    gtk_widget_set_halign(fallback_box_, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(fallback_box_, GTK_ALIGN_CENTER);
    gtk_widget_set_can_target(fallback_box_, FALSE);
    fallback_icon_ = gtk_image_new_from_icon_name("view-restore-symbolic");
    gtk_image_set_pixel_size(GTK_IMAGE(fallback_icon_), 40);
    fallback_title_ = gtk_label_new("");
    gtk_widget_add_css_class(fallback_title_, "cf-fallback-title");
    fallback_message_ = gtk_label_new("");
    gtk_widget_add_css_class(fallback_message_, "cf-fallback-message");
    gtk_label_set_wrap(GTK_LABEL(fallback_message_), TRUE);
    gtk_label_set_justify(GTK_LABEL(fallback_message_), GTK_JUSTIFY_CENTER);
    gtk_label_set_max_width_chars(GTK_LABEL(fallback_message_), 48);
    gtk_box_append(GTK_BOX(fallback_box_), fallback_icon_);
    gtk_box_append(GTK_BOX(fallback_box_), fallback_title_);
    gtk_box_append(GTK_BOX(fallback_box_), fallback_message_);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), fallback_box_);

    // Metrics badge, top-left.
    metrics_label_ = gtk_label_new("");
    gtk_widget_add_css_class(metrics_label_, "cf-metrics");
    gtk_widget_set_halign(metrics_label_, GTK_ALIGN_START);
    gtk_widget_set_valign(metrics_label_, GTK_ALIGN_START);
    gtk_widget_set_margin_start(metrics_label_, 10);
    gtk_widget_set_margin_top(metrics_label_, 10);
    gtk_widget_set_can_target(metrics_label_, FALSE);
    gtk_label_set_xalign(GTK_LABEL(metrics_label_), 0);
    gtk_overlay_add_overlay(GTK_OVERLAY(overlay), metrics_label_);

    apply_presentation_mode();
    apply_state();
    update_metrics();
}

int OutputWindow::on_close_request(GtkWindow*, void* user_data) {
    auto* self = static_cast<OutputWindow*>(user_data);
    // Closing hides; the window keeps its identity for the share picker.
    self->hide();
    return TRUE;
}

void OutputWindow::on_map(GtkWidget*, void* user_data) {
    auto* self = static_cast<OutputWindow*>(user_data);
    self->pin_applied_ = false;
    if (self->pin_on_top_) {
        // Give the compositor a moment to register the toplevel before dispatching.
        g_timeout_add_once(150, [](gpointer data) { static_cast<OutputWindow*>(data)->apply_pin(); }, self);
    }
}

void OutputWindow::show() {
    // Map without requesting activation, like orderFrontRegardless on macOS: the
    // output window should never steal focus from the window being followed.
    gtk_widget_set_visible(GTK_WIDGET(window_), TRUE);
    if (!visible_) {
        visible_ = true;
        fps_frames_ = 0;
        if (!fps_timer_) fps_timer_ = g_timeout_add(1000, &OutputWindow::on_fps_tick, this);
        g_message("Output window shown");
        if (on_visibility_changed) on_visibility_changed();
    }
}

void OutputWindow::hide() {
    if (!visible_) return;
    gtk_widget_set_visible(GTK_WIDGET(window_), FALSE);
    visible_ = false;
    if (fps_timer_) {
        g_source_remove(fps_timer_);
        fps_timer_ = 0;
    }
    current_fps_ = 0;
    g_message("Output window hidden");
    if (on_visibility_changed) on_visibility_changed();
}

void OutputWindow::toggle() {
    if (visible_) hide(); else show();
}

void OutputWindow::set_no_target() {
    target_title_.clear();
    state_ = OutputState::NoTarget;
    state_detail_.clear();
    capture_width_ = capture_height_ = 0;
    apply_state();
    update_metrics();
}

void OutputWindow::set_capture_unavailable(const std::string& message) {
    state_ = OutputState::CaptureUnavailable;
    state_detail_ = message;
    apply_state();
}

void OutputWindow::set_paused(const std::optional<std::string>& target_title) {
    if (target_title) target_title_ = *target_title;
    state_ = OutputState::Paused;
    state_detail_.clear();
    apply_state();
}

void OutputWindow::set_target_unavailable(const std::string& message) {
    state_ = OutputState::TargetUnavailable;
    state_detail_ = message;
    apply_state();
}

void OutputWindow::prepare_for_capture(const std::string& target_title) {
    target_title_ = target_title;
    state_ = OutputState::WaitingForFrames;
    state_detail_.clear();
    apply_state();
}

void OutputWindow::update_for_capture(int width, int height, const std::string& target_title) {
    if (width <= 0 || height <= 0) return;
    target_title_ = target_title;
    bool changed = width != capture_width_ || height != capture_height_;
    capture_width_ = width;
    capture_height_ = height;
    if (changed && presentation_mode_ == PresentationMode::Actual) resize_to_actual_size();
    if (state_ != OutputState::Live) {
        state_ = OutputState::WaitingForFrames;
        apply_state();
    }
    update_metrics();
}

void OutputWindow::present_frame(GdkTexture* texture, int width, int height) {
    gtk_picture_set_paintable(GTK_PICTURE(picture_), GDK_PAINTABLE(texture));
    ++fps_frames_;
    bool changed = width != capture_width_ || height != capture_height_;
    capture_width_ = width;
    capture_height_ = height;
    if (changed) {
        if (presentation_mode_ == PresentationMode::Actual) resize_to_actual_size();
        update_metrics();
    }
    if (state_ != OutputState::Live) {
        state_ = OutputState::Live;
        apply_state();
        update_metrics();
    }
}

void OutputWindow::set_presentation_mode(PresentationMode mode) {
    presentation_mode_ = mode;
    apply_presentation_mode();
}

void OutputWindow::set_show_resolution(bool show) {
    show_resolution_ = show;
    update_metrics();
}

void OutputWindow::set_show_frame_count(bool show) {
    show_frame_count_ = show;
    update_metrics();
}

void OutputWindow::set_pin_on_top(bool pin) {
    pin_on_top_ = pin;
    pin_applied_ = false;
    if (visible_) apply_pin();
}

void OutputWindow::apply_presentation_mode() {
    GtkContentFit fit = GTK_CONTENT_FIT_CONTAIN;
    switch (presentation_mode_) {
        case PresentationMode::Fit: fit = GTK_CONTENT_FIT_CONTAIN; break;
        case PresentationMode::Fill: fit = GTK_CONTENT_FIT_COVER; break;
        case PresentationMode::Actual: fit = GTK_CONTENT_FIT_CONTAIN; break;
    }
    gtk_picture_set_content_fit(GTK_PICTURE(picture_), fit);
    if (presentation_mode_ == PresentationMode::Actual) resize_to_actual_size();
}

void OutputWindow::resize_to_actual_size() {
    if (capture_width_ <= 0 || capture_height_ <= 0) return;
    int scale = gtk_widget_get_scale_factor(GTK_WIDGET(window_));
    if (scale < 1) scale = 1;
    // Tiled Hyprland windows ignore this; floating ones honour it.
    gtk_window_set_default_size(window_, capture_width_ / scale, capture_height_ / scale);
}

void OutputWindow::apply_state() {
    const char* icon = nullptr;
    const char* title = nullptr;
    std::string message;
    switch (state_) {
        case OutputState::Live:
            break;
        case OutputState::NoTarget:
            icon = "view-restore-symbolic";
            title = "No Target Selected";
            message = "Choose a window in CursorFollow to start sharing.";
            break;
        case OutputState::CaptureUnavailable:
            icon = "dialog-warning-symbolic";
            title = "Capture Unavailable";
            message = state_detail_.empty() ? "This compositor does not support per-window capture." : state_detail_;
            break;
        case OutputState::Paused:
            icon = "media-playback-pause-symbolic";
            title = "Output Paused";
            message = target_title_.empty() ? "Start capture when you are ready." : "Ready to resume " + target_title_ + ".";
            break;
        case OutputState::TargetUnavailable:
            icon = "dialog-warning-symbolic";
            title = "Target Unavailable";
            message = state_detail_.empty() ? "The selected window closed or is no longer capturable." : state_detail_;
            break;
        case OutputState::WaitingForFrames:
            icon = "view-refresh-symbolic";
            title = "Preparing Output";
            message = target_title_.empty() ? "Waiting for the first captured frame." : "Waiting for the first frame from " + target_title_ + ".";
            break;
    }
    if (!title) {
        gtk_widget_set_visible(fallback_box_, FALSE);
        return;
    }
    gtk_image_set_from_icon_name(GTK_IMAGE(fallback_icon_), icon);
    gtk_label_set_text(GTK_LABEL(fallback_title_), title);
    gtk_label_set_text(GTK_LABEL(fallback_message_), message.c_str());
    gtk_widget_set_visible(fallback_box_, TRUE);
}

void OutputWindow::update_metrics() {
    std::string text;
    if (show_resolution_ && capture_width_ > 0) {
        text += std::to_string(capture_width_) + "×" + std::to_string(capture_height_);
    }
    if (show_frame_count_) {
        char buf[32];
        std::snprintf(buf, sizeof buf, "%.0f fps", current_fps_);
        if (!text.empty()) text += "\n";
        text += buf;
    }
    gtk_label_set_text(GTK_LABEL(metrics_label_), text.c_str());
    gtk_widget_set_visible(metrics_label_, !text.empty());
}

int OutputWindow::on_fps_tick(void* user_data) {
    auto* self = static_cast<OutputWindow*>(user_data);
    self->current_fps_ = static_cast<double>(self->fps_frames_);
    self->fps_frames_ = 0;
    if (self->show_frame_count_) self->update_metrics();
    return G_SOURCE_CONTINUE;
}

void OutputWindow::apply_pin() {
    if (pin_applied_ || !visible_) return;
    // Hyprland has no "always on top" for tiled windows; a pinned floating window is
    // the nearest thing (shown on every workspace, above tiles).
    auto reply = ipc_.request("j/clients");
    if (!reply) return;
    std::string address;
    bool floating = false;
    bool pinned = false;
    {
        std::vector<TrackedWindow> all;
        if (!hyprland_clients::parse_clients(*reply, all)) return;
        for (const auto& w : all) {
            if (w.app_id == kAppId && w.title == kOutputWindowTitle) {
                address = w.address_hex();
                floating = w.floating;
                pinned = w.pinned;
                break;
            }
        }
    }
    if (address.empty()) return;
    const std::string target = "address:" + address;
    std::string err;
    if (pin_on_top_) {
        if (!floating) {
            ipc_.dispatch("hl.dsp.window.float({ window = \"" + target + "\", action = \"toggle\" })", "togglefloating " + target, &err);
        }
        if (!pinned) {
            ipc_.dispatch("hl.dsp.window.pin({ window = \"" + target + "\" })", "pin " + target, &err);
        }
    } else if (pinned) {
        ipc_.dispatch("hl.dsp.window.pin({ window = \"" + target + "\" })", "pin " + target, &err);
    }
    if (!err.empty()) g_warning("Pin on top: %s", err.c_str());
    pin_applied_ = true;
}

}  // namespace cf
