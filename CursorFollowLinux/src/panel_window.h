#pragma once

#include <functional>
#include <string>

#include "app_settings.h"
#include "tracked_window.h"

typedef struct _GtkApplication GtkApplication;
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkListBoxRow GtkListBoxRow;
typedef struct _GtkListBox GtkListBox;
typedef struct _GtkToggleButton GtkToggleButton;
typedef struct _GtkButton GtkButton;
typedef struct _GtkGesture GtkGesture;

namespace cf {

class App;

/// The compact control panel: target mode, filter, window list and the three
/// action buttons. The Linux equivalent of the macOS menu-bar popover.
class PanelWindow {
public:
    PanelWindow(GtkApplication* gtk_app, App& app);
    ~PanelWindow();

    PanelWindow(const PanelWindow&) = delete;
    PanelWindow& operator=(const PanelWindow&) = delete;

    void show();
    GtkWindow* window() const { return window_; }

    /// Re-reads every piece of app state and redraws.
    void refresh();
    void refresh_window_list();

private:
    void build();
    void open_settings();
    void confirm_quit();
    GtkWidget* make_window_row(const TrackedWindow& window);

    static void on_target_mode_toggled(GtkToggleButton* button, void* user_data);
    static void on_filter_toggled(GtkToggleButton* button, void* user_data);
    static void on_row_activated(GtkListBox* list, GtkListBoxRow* row, void* user_data);
    static void on_row_secondary_click(GtkGesture* gesture, int n_press, double x, double y, void* user_data);
    static void on_refresh_clicked(GtkButton* button, void* user_data);
    static void on_toggle_output_clicked(GtkButton* button, void* user_data);
    static void on_toggle_capture_clicked(GtkButton* button, void* user_data);
    static void on_settings_clicked(GtkButton* button, void* user_data);
    static void on_quit_clicked(GtkButton* button, void* user_data);

    App& app_;
    GtkApplication* gtk_app_ = nullptr;
    GtkWindow* window_ = nullptr;
    GtkWidget* status_badge_ = nullptr;
    GtkWidget* mode_auto_ = nullptr;
    GtkWidget* mode_manual_ = nullptr;
    GtkWidget* filter_all_ = nullptr;
    GtkWidget* filter_exclude_ = nullptr;
    GtkWidget* filter_include_ = nullptr;
    GtkWidget* list_ = nullptr;
    GtkWidget* list_stack_ = nullptr;
    GtkWidget* empty_title_ = nullptr;
    GtkWidget* empty_hint_ = nullptr;
    GtkWidget* toggle_output_button_ = nullptr;
    GtkWidget* toggle_capture_button_ = nullptr;
    GtkWidget* status_line_ = nullptr;
    bool updating_ = false;
};

}  // namespace cf
