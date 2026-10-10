#include "panel_window.h"

#include <gtk/gtk.h>

#include "app.h"
#include "settings_window.h"

namespace cf {

namespace {

struct RowData {
    TrackedWindow window;
};

void row_data_free(gpointer p) { delete static_cast<RowData*>(p); }

GtkWidget* caption(const char* text) {
    GtkWidget* label = gtk_label_new(text);
    gtk_widget_add_css_class(label, "cf-caption");
    gtk_label_set_xalign(GTK_LABEL(label), 0);
    return label;
}

GtkWidget* icon_button(const char* icon, const char* tooltip) {
    GtkWidget* button = gtk_button_new_from_icon_name(icon);
    gtk_widget_add_css_class(button, "flat");
    gtk_widget_set_tooltip_text(button, tooltip);
    return button;
}

}  // namespace

PanelWindow::PanelWindow(GtkApplication* gtk_app, App& app) : app_(app), gtk_app_(gtk_app) {
    build();
}

PanelWindow::~PanelWindow() {
    if (window_) gtk_window_destroy(window_);
}

void PanelWindow::build() {
    window_ = GTK_WINDOW(gtk_application_window_new(gtk_app_));
    gtk_window_set_title(window_, "CursorFollow");
    gtk_window_set_default_size(window_, 360, 640);
    gtk_window_set_hide_on_close(window_, TRUE);
    gtk_widget_add_css_class(GTK_WIDGET(window_), "cf-panel");

    GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    gtk_widget_set_margin_top(root, 12);
    gtk_widget_set_margin_bottom(root, 12);
    gtk_widget_set_margin_start(root, 12);
    gtk_widget_set_margin_end(root, 12);
    gtk_window_set_child(window_, root);

    // Header: icon, title, status badge, settings, quit.
    GtkWidget* header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget* app_icon = gtk_image_new_from_icon_name("camera-video-symbolic");
    gtk_widget_add_css_class(app_icon, "accent");
    GtkWidget* title = gtk_label_new("CursorFollow");
    gtk_widget_add_css_class(title, "title-2");
    status_badge_ = gtk_label_new("IDLE");
    gtk_widget_add_css_class(status_badge_, "cf-badge");
    GtkWidget* settings_button = icon_button("emblem-system-symbolic", "Settings");
    g_signal_connect(settings_button, "clicked", G_CALLBACK(&PanelWindow::on_settings_clicked), this);
    GtkWidget* quit_button = icon_button("window-close-symbolic", "Quit CursorFollow");
    g_signal_connect(quit_button, "clicked", G_CALLBACK(&PanelWindow::on_quit_clicked), this);
    gtk_box_append(GTK_BOX(header), app_icon);
    gtk_box_append(GTK_BOX(header), title);
    GtkWidget* spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(spacer, TRUE);
    gtk_box_append(GTK_BOX(header), spacer);
    gtk_box_append(GTK_BOX(header), status_badge_);
    gtk_box_append(GTK_BOX(header), settings_button);
    gtk_box_append(GTK_BOX(header), quit_button);
    gtk_box_append(GTK_BOX(root), header);

    // Target mode.
    GtkWidget* mode_card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_add_css_class(mode_card, "cf-card");
    gtk_box_append(GTK_BOX(mode_card), caption("TARGET MODE"));
    GtkWidget* mode_group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(mode_group, "linked");
    gtk_box_set_homogeneous(GTK_BOX(mode_group), TRUE);
    mode_auto_ = gtk_toggle_button_new_with_label("Auto");
    mode_manual_ = gtk_toggle_button_new_with_label("Manual");
    gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(mode_manual_), GTK_TOGGLE_BUTTON(mode_auto_));
    gtk_widget_set_tooltip_text(mode_auto_, "Follow the focused window");
    gtk_widget_set_tooltip_text(mode_manual_, "Keep the selected window");
    g_signal_connect(mode_auto_, "toggled", G_CALLBACK(&PanelWindow::on_target_mode_toggled), this);
    gtk_box_append(GTK_BOX(mode_group), mode_auto_);
    gtk_box_append(GTK_BOX(mode_group), mode_manual_);
    gtk_box_append(GTK_BOX(mode_card), mode_group);
    gtk_box_append(GTK_BOX(root), mode_card);

    // Filter.
    GtkWidget* filter_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_tooltip_text(filter_row, "All: follow any window. Exclude: skip selected apps. Include: only follow selected apps.");
    GtkWidget* filter_caption = caption("FILTER");
    gtk_widget_set_hexpand(filter_caption, TRUE);
    gtk_box_append(GTK_BOX(filter_row), filter_caption);
    GtkWidget* filter_group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(filter_group, "linked");
    filter_all_ = gtk_toggle_button_new_with_label("All");
    filter_exclude_ = gtk_toggle_button_new_with_label("Exclude");
    filter_include_ = gtk_toggle_button_new_with_label("Include");
    gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(filter_exclude_), GTK_TOGGLE_BUTTON(filter_all_));
    gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(filter_include_), GTK_TOGGLE_BUTTON(filter_all_));
    for (GtkWidget* b : {filter_all_, filter_exclude_, filter_include_}) {
        g_signal_connect(b, "toggled", G_CALLBACK(&PanelWindow::on_filter_toggled), this);
        gtk_box_append(GTK_BOX(filter_group), b);
    }
    gtk_box_append(GTK_BOX(filter_row), filter_group);
    gtk_box_append(GTK_BOX(root), filter_row);

    // Window list (or the empty state).
    list_stack_ = gtk_stack_new();
    gtk_widget_set_vexpand(list_stack_, TRUE);
    gtk_widget_add_css_class(list_stack_, "cf-card");

    GtkWidget* scroller = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    list_ = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(list_), GTK_SELECTION_NONE);
    gtk_widget_add_css_class(list_, "cf-list");
    g_signal_connect(list_, "row-activated", G_CALLBACK(&PanelWindow::on_row_activated), this);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), list_);
    gtk_stack_add_named(GTK_STACK(list_stack_), scroller, "list");

    GtkWidget* empty = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_valign(empty, GTK_ALIGN_CENTER);
    GtkWidget* empty_icon = gtk_image_new_from_icon_name("window-close-symbolic");
    gtk_image_set_pixel_size(GTK_IMAGE(empty_icon), 36);
    gtk_widget_add_css_class(empty_icon, "dim-label");
    empty_title_ = gtk_label_new("No windows available");
    gtk_widget_add_css_class(empty_title_, "dim-label");
    empty_hint_ = gtk_label_new("");
    gtk_widget_add_css_class(empty_hint_, "cf-hint");
    gtk_label_set_wrap(GTK_LABEL(empty_hint_), TRUE);
    gtk_label_set_justify(GTK_LABEL(empty_hint_), GTK_JUSTIFY_CENTER);
    gtk_box_append(GTK_BOX(empty), empty_icon);
    gtk_box_append(GTK_BOX(empty), empty_title_);
    gtk_box_append(GTK_BOX(empty), empty_hint_);
    gtk_stack_add_named(GTK_STACK(list_stack_), empty, "empty");
    gtk_box_append(GTK_BOX(root), list_stack_);

    // Controls.
    GtkWidget* controls = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget* refresh_button = gtk_button_new_with_label("Refresh");
    gtk_widget_set_tooltip_text(refresh_button, "Refresh window list");
    g_signal_connect(refresh_button, "clicked", G_CALLBACK(&PanelWindow::on_refresh_clicked), this);
    GtkWidget* controls_spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(controls_spacer, TRUE);
    toggle_output_button_ = gtk_button_new_with_label("Show");
    gtk_widget_set_tooltip_text(toggle_output_button_, "Show or hide the CursorFollow Output window");
    g_signal_connect(toggle_output_button_, "clicked", G_CALLBACK(&PanelWindow::on_toggle_output_clicked), this);
    toggle_capture_button_ = gtk_button_new_with_label("Resume");
    gtk_widget_add_css_class(toggle_capture_button_, "suggested-action");
    g_signal_connect(toggle_capture_button_, "clicked", G_CALLBACK(&PanelWindow::on_toggle_capture_clicked), this);
    gtk_box_append(GTK_BOX(controls), refresh_button);
    gtk_box_append(GTK_BOX(controls), controls_spacer);
    gtk_box_append(GTK_BOX(controls), toggle_output_button_);
    gtk_box_append(GTK_BOX(controls), toggle_capture_button_);
    gtk_box_append(GTK_BOX(root), controls);

    status_line_ = gtk_label_new("");
    gtk_widget_add_css_class(status_line_, "cf-hint");
    gtk_label_set_xalign(GTK_LABEL(status_line_), 0);
    gtk_label_set_ellipsize(GTK_LABEL(status_line_), PANGO_ELLIPSIZE_END);
    gtk_box_append(GTK_BOX(root), status_line_);

    refresh();
}

void PanelWindow::show() {
    gtk_window_present(window_);
}

void PanelWindow::refresh() {
    updating_ = true;
    const WindowTracker& tracker = app_.tracker();
    const CaptureEngine& engine = app_.engine();

    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(tracker.auto_follow_enabled() ? mode_auto_ : mode_manual_), TRUE);
    switch (tracker.filter_mode()) {
        case FilterMode::All: gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(filter_all_), TRUE); break;
        case FilterMode::Exclude: gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(filter_exclude_), TRUE); break;
        case FilterMode::Include: gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(filter_include_), TRUE); break;
    }

    const char* badge = engine.is_capturing() ? "LIVE" : (engine.user_stopped() ? "PAUSED" : "IDLE");
    gtk_label_set_text(GTK_LABEL(status_badge_), badge);
    gtk_widget_remove_css_class(status_badge_, "cf-badge-live");
    if (engine.is_capturing()) gtk_widget_add_css_class(status_badge_, "cf-badge-live");

    gtk_button_set_label(GTK_BUTTON(toggle_output_button_), app_.output().is_visible() ? "Hide" : "Show");
    gtk_button_set_label(GTK_BUTTON(toggle_capture_button_), engine.is_capturing() ? "Pause" : "Resume");
    gtk_widget_set_sensitive(toggle_capture_button_, engine.supported());

    std::string status;
    if (!tracker.error().empty()) {
        status = tracker.error();
    } else if (!engine.supported()) {
        status = engine.error();
    } else if (engine.is_capturing() && engine.target()) {
        status = std::string(tracker.auto_follow_enabled() ? "Following: " : "Locked to: ") + engine.target()->title;
    } else if (engine.last_error()) {
        status = *engine.last_error();
    } else if (tracker.target_unavailable_message()) {
        status = *tracker.target_unavailable_message();
    } else if (tracker.selected()) {
        status = "Selected: " + tracker.selected()->title;
    } else {
        status = tracker.auto_follow_enabled() ? "Resume to follow the focused window." : "Pick a window, then Resume.";
    }
    gtk_label_set_text(GTK_LABEL(status_line_), status.c_str());
    gtk_widget_set_tooltip_text(status_line_, status.c_str());

    refresh_window_list();
    updating_ = false;
}

GtkWidget* PanelWindow::make_window_row(const TrackedWindow& window) {
    const WindowTracker& tracker = app_.tracker();
    const bool selected = tracker.selected() && *tracker.selected() == window;
    const bool in_list = tracker.is_in_active_list(window);

    GtkWidget* row = gtk_list_box_row_new();
    auto* data = new RowData{window};
    g_object_set_data_full(G_OBJECT(row), "cf-window", data, row_data_free);

    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_set_margin_top(box, 6);
    gtk_widget_set_margin_bottom(box, 6);
    gtk_widget_set_margin_start(box, 10);
    gtk_widget_set_margin_end(box, 10);

    GtkWidget* check = gtk_image_new_from_icon_name(selected ? "object-select-symbolic" : "");
    gtk_widget_set_size_request(check, 16, -1);
    gtk_widget_set_opacity(check, selected ? 1.0 : 0.0);
    gtk_box_append(GTK_BOX(box), check);

    GtkWidget* text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_hexpand(text, TRUE);
    GtkWidget* title = gtk_label_new(window.title.c_str());
    gtk_label_set_xalign(GTK_LABEL(title), 0);
    gtk_label_set_ellipsize(GTK_LABEL(title), PANGO_ELLIPSIZE_END);
    gtk_widget_add_css_class(title, "cf-row-title");
    std::string detail = window.app_id + "  ·  " + window.size_label();
    GtkWidget* subtitle = gtk_label_new(detail.c_str());
    gtk_label_set_xalign(GTK_LABEL(subtitle), 0);
    gtk_label_set_ellipsize(GTK_LABEL(subtitle), PANGO_ELLIPSIZE_END);
    gtk_widget_add_css_class(subtitle, "cf-row-subtitle");
    gtk_box_append(GTK_BOX(text), title);
    gtk_box_append(GTK_BOX(text), subtitle);
    gtk_box_append(GTK_BOX(box), text);

    if (tracker.filter_mode() != FilterMode::All) {
        const char* badge_text = tracker.filter_mode() == FilterMode::Exclude
            ? (in_list ? "Excluded" : "")
            : (in_list ? "Included" : "");
        if (*badge_text) {
            GtkWidget* badge = gtk_label_new(badge_text);
            gtk_widget_add_css_class(badge, "cf-badge");
            gtk_widget_set_valign(badge, GTK_ALIGN_CENTER);
            gtk_box_append(GTK_BOX(box), badge);
        }
    }
    if (selected) gtk_widget_add_css_class(row, "cf-row-selected");
    if (in_list && tracker.filter_mode() == FilterMode::Exclude) gtk_widget_add_css_class(row, "cf-row-dimmed");

    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);

    // Right-click: switch regardless of filter mode (the macOS context menu item).
    GtkGesture* click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), GDK_BUTTON_SECONDARY);
    g_signal_connect(click, "pressed", G_CALLBACK(&PanelWindow::on_row_secondary_click), this);
    gtk_widget_add_controller(row, GTK_EVENT_CONTROLLER(click));
    gtk_widget_set_tooltip_text(row, tracker.filter_mode() == FilterMode::All
        ? "Click to switch to this window"
        : "Click to toggle this app in the filter list. Right-click to switch to it.");
    return row;
}

void PanelWindow::refresh_window_list() {
    while (GtkWidget* child = gtk_widget_get_first_child(list_)) {
        gtk_list_box_remove(GTK_LIST_BOX(list_), child);
    }
    const WindowTracker& tracker = app_.tracker();
    if (tracker.windows().empty()) {
        std::string hint = tracker.error().empty()
            ? "Open or focus a window, then refresh."
            : tracker.error();
        gtk_label_set_text(GTK_LABEL(empty_hint_), hint.c_str());
        gtk_stack_set_visible_child_name(GTK_STACK(list_stack_), "empty");
        return;
    }
    for (const auto& w : tracker.windows()) {
        gtk_list_box_append(GTK_LIST_BOX(list_), make_window_row(w));
    }
    gtk_stack_set_visible_child_name(GTK_STACK(list_stack_), "list");
}

void PanelWindow::on_target_mode_toggled(GtkToggleButton* button, void* user_data) {
    auto* self = static_cast<PanelWindow*>(user_data);
    if (self->updating_) return;
    self->app_.set_auto_follow(gtk_toggle_button_get_active(button) != FALSE);
}

void PanelWindow::on_filter_toggled(GtkToggleButton* button, void* user_data) {
    auto* self = static_cast<PanelWindow*>(user_data);
    if (self->updating_ || !gtk_toggle_button_get_active(button)) return;
    FilterMode mode = FilterMode::All;
    if (GTK_WIDGET(button) == self->filter_exclude_) mode = FilterMode::Exclude;
    if (GTK_WIDGET(button) == self->filter_include_) mode = FilterMode::Include;
    self->app_.set_filter_mode(mode);
}

void PanelWindow::on_row_activated(GtkListBox*, GtkListBoxRow* row, void* user_data) {
    auto* self = static_cast<PanelWindow*>(user_data);
    auto* data = static_cast<RowData*>(g_object_get_data(G_OBJECT(row), "cf-window"));
    if (!data) return;
    if (self->app_.tracker().filter_mode() != FilterMode::All) {
        self->app_.toggle_filter_membership(data->window);
    } else {
        self->app_.select_window(data->window);
    }
}

void PanelWindow::on_row_secondary_click(GtkGesture* gesture, int, double, double, void* user_data) {
    auto* self = static_cast<PanelWindow*>(user_data);
    GtkWidget* row = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
    auto* data = static_cast<RowData*>(g_object_get_data(G_OBJECT(row), "cf-window"));
    if (data) self->app_.select_window(data->window);
}

void PanelWindow::on_refresh_clicked(GtkButton*, void* user_data) {
    static_cast<PanelWindow*>(user_data)->app_.refresh_windows();
}

void PanelWindow::on_toggle_output_clicked(GtkButton*, void* user_data) {
    static_cast<PanelWindow*>(user_data)->app_.toggle_output();
}

void PanelWindow::on_toggle_capture_clicked(GtkButton*, void* user_data) {
    static_cast<PanelWindow*>(user_data)->app_.toggle_capture();
}

void PanelWindow::on_settings_clicked(GtkButton*, void* user_data) {
    static_cast<PanelWindow*>(user_data)->open_settings();
}

void PanelWindow::on_quit_clicked(GtkButton*, void* user_data) {
    static_cast<PanelWindow*>(user_data)->confirm_quit();
}

void PanelWindow::open_settings() {
    show_settings_window(window_, app_);
}

void PanelWindow::confirm_quit() {
    GtkAlertDialog* dialog = gtk_alert_dialog_new("Quit CursorFollow?");
    gtk_alert_dialog_set_detail(dialog, "The CursorFollow Output window will close and any share of it will end.");
    const char* buttons[] = {"Cancel", "Quit", nullptr};
    gtk_alert_dialog_set_buttons(dialog, buttons);
    gtk_alert_dialog_set_default_button(dialog, 0);
    gtk_alert_dialog_set_cancel_button(dialog, 0);
    gtk_alert_dialog_choose(dialog, window_, nullptr, [](GObject* source, GAsyncResult* result, gpointer data) {
        int choice = gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(source), result, nullptr);
        if (choice == 1) static_cast<App*>(data)->quit();
    }, &app_);
    g_object_unref(dialog);
}

}  // namespace cf
