#include "settings_window.h"

#include <gtk/gtk.h>

#include <string>

#include "app.h"

namespace cf {

namespace {

GtkWindow* g_open_window = nullptr;

GtkWidget* section(GtkWidget* parent, const char* title) {
    GtkWidget* label = gtk_label_new(title);
    gtk_widget_add_css_class(label, "cf-caption");
    gtk_label_set_xalign(GTK_LABEL(label), 0);
    gtk_widget_set_margin_top(label, 8);
    gtk_box_append(GTK_BOX(parent), label);
    GtkWidget* list = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(list), GTK_SELECTION_NONE);
    gtk_widget_add_css_class(list, "boxed-list");
    gtk_box_append(GTK_BOX(parent), list);
    return list;
}

GtkWidget* row_with(const char* title, const char* subtitle, GtkWidget* control) {
    GtkWidget* row = gtk_list_box_row_new();
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), FALSE);
    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk_widget_set_margin_top(box, 8);
    gtk_widget_set_margin_bottom(box, 8);
    gtk_widget_set_margin_start(box, 12);
    gtk_widget_set_margin_end(box, 12);
    GtkWidget* text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_hexpand(text, TRUE);
    gtk_widget_set_valign(text, GTK_ALIGN_CENTER);
    GtkWidget* t = gtk_label_new(title);
    gtk_label_set_xalign(GTK_LABEL(t), 0);
    gtk_box_append(GTK_BOX(text), t);
    if (subtitle && *subtitle) {
        GtkWidget* s = gtk_label_new(subtitle);
        gtk_label_set_xalign(GTK_LABEL(s), 0);
        gtk_label_set_wrap(GTK_LABEL(s), TRUE);
        gtk_widget_add_css_class(s, "cf-row-subtitle");
        gtk_box_append(GTK_BOX(text), s);
    }
    gtk_box_append(GTK_BOX(box), text);
    gtk_widget_set_valign(control, GTK_ALIGN_CENTER);
    gtk_box_append(GTK_BOX(box), control);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
    return row;
}

using SwitchHandler = void (*)(App&, bool);

struct SwitchBinding {
    App* app;
    SwitchHandler handler;
};

void on_switch_state(GtkSwitch*, gboolean state, gpointer data) {
    auto* b = static_cast<SwitchBinding*>(data);
    b->handler(*b->app, state != FALSE);
}

void add_switch(GtkWidget* list, App& app, const char* title, const char* subtitle, bool initial, SwitchHandler handler) {
    GtkWidget* sw = gtk_switch_new();
    gtk_switch_set_active(GTK_SWITCH(sw), initial);
    auto* binding = new SwitchBinding{&app, handler};
    g_object_set_data_full(G_OBJECT(sw), "cf-binding", binding, [](gpointer p) { delete static_cast<SwitchBinding*>(p); });
    g_signal_connect(sw, "state-set", G_CALLBACK(+[](GtkSwitch* s, gboolean state, gpointer data) -> gboolean {
        on_switch_state(s, state, data);
        return FALSE;
    }), binding);
    gtk_list_box_append(GTK_LIST_BOX(list), row_with(title, subtitle, sw));
}

using DropdownHandler = void (*)(App&, unsigned index);

struct DropdownBinding {
    App* app;
    DropdownHandler handler;
};

void add_dropdown(GtkWidget* list, App& app, const char* title, const char* subtitle, const char* const* options,
                  unsigned initial, DropdownHandler handler) {
    GtkWidget* dd = gtk_drop_down_new_from_strings(options);
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dd), initial);
    auto* binding = new DropdownBinding{&app, handler};
    g_object_set_data_full(G_OBJECT(dd), "cf-binding", binding, [](gpointer p) { delete static_cast<DropdownBinding*>(p); });
    g_signal_connect(dd, "notify::selected", G_CALLBACK(+[](GObject* obj, GParamSpec*, gpointer data) {
        auto* b = static_cast<DropdownBinding*>(data);
        b->handler(*b->app, gtk_drop_down_get_selected(GTK_DROP_DOWN(obj)));
    }), binding);
    gtk_list_box_append(GTK_LIST_BOX(list), row_with(title, subtitle, dd));
}

}  // namespace

void show_settings_window(GtkWindow* parent, App& app) {
    if (g_open_window) {
        gtk_window_present(g_open_window);
        return;
    }
    AppSettings& s = app.settings();

    GtkWindow* window = GTK_WINDOW(gtk_window_new());
    // Attach to the application so the Wayland app_id is ours and the tracker skips it.
    gtk_window_set_application(window, gtk_window_get_application(parent));
    gtk_window_set_title(window, "CursorFollow Settings");
    gtk_window_set_transient_for(window, parent);
    gtk_window_set_modal(window, FALSE);
    gtk_window_set_default_size(window, 460, 640);
    gtk_widget_add_css_class(GTK_WIDGET(window), "cf-panel");
    g_open_window = window;
    g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer) { g_open_window = nullptr; }), nullptr);

    GtkWidget* scroller = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_window_set_child(window, scroller);
    GtkWidget* root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    gtk_widget_set_margin_top(root, 12);
    gtk_widget_set_margin_bottom(root, 12);
    gtk_widget_set_margin_start(root, 12);
    gtk_widget_set_margin_end(root, 12);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), root);

    GtkWidget* general = section(root, "GENERAL");
    add_switch(general, app, "Start on login", "Adds an XDG autostart entry for this binary.", s.start_on_login(),
               [](App& a, bool v) { a.set_start_on_login(v); });
    add_switch(general, app, "Auto share on start", "Begin following the focused window as soon as CursorFollow launches.",
               s.auto_share_on_start(), [](App& a, bool v) { a.settings().set_auto_share_on_start(v); });

    GtkWidget* output = section(root, "OUTPUT WINDOW");
    add_switch(output, app, "Hide when not sharing", "Hide CursorFollow Output while capture is paused or has no target.",
               s.hide_when_not_sharing(), [](App& a, bool v) { a.set_hide_when_not_sharing(v); });
    add_switch(output, app, "Pin output on top", "Float and pin the output window so it stays above tiled windows.",
               s.pin_output_on_top(), [](App& a, bool v) { a.set_pin_output_on_top(v); });
    add_switch(output, app, "Show resolution", "Overlay the capture size in the corner of the output.",
               s.show_resolution(), [](App& a, bool v) { a.set_show_resolution(v); });
    add_switch(output, app, "Show frame rate", "Overlay the delivered frames per second.",
               s.show_frame_count(), [](App& a, bool v) { a.set_show_frame_count(v); });
    static const char* const scaling[] = {"Fit", "Fill", "Actual", nullptr};
    unsigned scaling_index = s.presentation_mode() == PresentationMode::Fit ? 0 : s.presentation_mode() == PresentationMode::Fill ? 1 : 2;
    add_dropdown(output, app, "Output scaling", "Fit letterboxes, Fill crops, Actual sizes the window to the capture.",
                 scaling, scaling_index, [](App& a, unsigned i) {
                     a.set_presentation_mode(i == 0 ? PresentationMode::Fit : i == 1 ? PresentationMode::Fill : PresentationMode::Actual);
                 });

    GtkWidget* capture = section(root, "CAPTURE");
    static const char* const quality[] = {"Balanced (30 fps)", "Smooth (60 fps)", "Efficient (15 fps)", nullptr};
    unsigned quality_index = s.capture_quality() == CaptureQuality::Balanced ? 0 : s.capture_quality() == CaptureQuality::Smooth ? 1 : 2;
    add_dropdown(capture, app, "Quality", "Frame-rate ceiling. Frames are only copied when the target changes.",
                 quality, quality_index, [](App& a, unsigned i) {
                     a.set_capture_quality(i == 0 ? CaptureQuality::Balanced : i == 1 ? CaptureQuality::Smooth : CaptureQuality::Efficient);
                 });

    GtkWidget* shortcuts = section(root, "SHORTCUTS");
    GtkWidget* hint = gtk_label_new(
        "Global shortcuts are bound in your compositor. Each command talks to the running instance.\n\n"
        "Hyprland (~/.config/hypr/bindings.lua):\n"
        "  o.bind(\"CTRL + ALT + F\", \"CursorFollow: toggle auto-follow\", \"cursorfollow --toggle-follow\")\n"
        "  o.bind(\"CTRL + ALT + S\", \"CursorFollow: toggle output\", \"cursorfollow --toggle-output\")\n\n"
        "Also: --pause, --resume, --toggle-capture, --show-panel, --settings");
    gtk_label_set_xalign(GTK_LABEL(hint), 0);
    gtk_label_set_wrap(GTK_LABEL(hint), TRUE);
    gtk_label_set_selectable(GTK_LABEL(hint), TRUE);
    gtk_widget_add_css_class(hint, "cf-row-subtitle");
    gtk_widget_set_margin_top(hint, 8);
    gtk_widget_set_margin_bottom(hint, 8);
    gtk_widget_set_margin_start(hint, 12);
    gtk_widget_set_margin_end(hint, 12);
    GtkWidget* hint_row = gtk_list_box_row_new();
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(hint_row), FALSE);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(hint_row), hint);
    gtk_list_box_append(GTK_LIST_BOX(shortcuts), hint_row);

    GtkWidget* about = section(root, "ABOUT");
    std::string version = std::string("CursorFollow for Linux ") + CF_VERSION + "\nSettings file: " + s.path();
    GtkWidget* about_label = gtk_label_new(version.c_str());
    gtk_label_set_xalign(GTK_LABEL(about_label), 0);
    gtk_label_set_wrap(GTK_LABEL(about_label), TRUE);
    gtk_label_set_selectable(GTK_LABEL(about_label), TRUE);
    gtk_widget_add_css_class(about_label, "cf-row-subtitle");
    gtk_widget_set_margin_top(about_label, 8);
    gtk_widget_set_margin_bottom(about_label, 8);
    gtk_widget_set_margin_start(about_label, 12);
    gtk_widget_set_margin_end(about_label, 12);
    GtkWidget* about_row = gtk_list_box_row_new();
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(about_row), FALSE);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(about_row), about_label);
    gtk_list_box_append(GTK_LIST_BOX(about), about_row);

    gtk_window_present(window);
}

}  // namespace cf
