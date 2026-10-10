// CursorFollow for Linux: entry point. GtkApplication gives us single-instance
// behaviour over D-Bus for free, which is what turns the command-line flags into
// remote controls for compositor key bindings.

#include <gtk/gtk.h>

#include <memory>

#include "app.h"
#include "tracked_window.h"

namespace {

std::unique_ptr<cf::App> g_app;

void on_startup(GtkApplication* gtk_app, gpointer) {
    g_app = std::make_unique<cf::App>(gtk_app);
    g_app->startup();
}

void on_activate(GtkApplication*, gpointer) {
    if (g_app) g_app->show_panel();
}

void on_shutdown(GtkApplication*, gpointer) {
    g_app.reset();
}

int on_command_line(GApplication* gapp, GApplicationCommandLine* cmdline, gpointer) {
    GVariantDict* options = g_application_command_line_get_options_dict(cmdline);
    bool handled = false;
    auto flag = [&](const char* name) {
        gboolean v = FALSE;
        return g_variant_dict_lookup(options, name, "b", &v) && v;
    };

    if (!g_app) {
        // Primary instance still starting; fall through to activate below.
    } else {
        if (flag("toggle-follow")) { g_app->toggle_auto_follow(); handled = true; }
        if (flag("toggle-output")) { g_app->toggle_output(); handled = true; }
        if (flag("toggle-capture")) { g_app->toggle_capture(); handled = true; }
        if (flag("pause")) { g_app->pause_capture(); handled = true; }
        if (flag("resume")) { g_app->resume_capture(); handled = true; }
        if (flag("quit")) { g_app->quit(); handled = true; }
        if (flag("show-panel")) { g_app->show_panel(); handled = true; }
        if (flag("settings")) { g_app->show_settings(); handled = true; }
    }
    if (!handled) g_application_activate(gapp);
    return 0;
}

int on_handle_local_options(GApplication*, GVariantDict* options, gpointer) {
    gboolean version = FALSE;
    if (g_variant_dict_lookup(options, "version", "b", &version) && version) {
        g_print("cursorfollow %s\n", CF_VERSION);
        return 0;
    }
    return -1;  // continue to the primary instance
}

}  // namespace

int main(int argc, char** argv) {
    g_set_prgname("cursorfollow");
    g_set_application_name("CursorFollow");

    GtkApplication* gtk_app = gtk_application_new(cf::kAppId, G_APPLICATION_HANDLES_COMMAND_LINE);

    static const GOptionEntry entries[] = {
        {"toggle-follow", 0, 0, G_OPTION_ARG_NONE, nullptr, "Toggle Auto/Manual target mode", nullptr},
        {"toggle-output", 0, 0, G_OPTION_ARG_NONE, nullptr, "Show or hide the CursorFollow Output window", nullptr},
        {"toggle-capture", 0, 0, G_OPTION_ARG_NONE, nullptr, "Pause or resume capture", nullptr},
        {"pause", 0, 0, G_OPTION_ARG_NONE, nullptr, "Pause capture", nullptr},
        {"resume", 0, 0, G_OPTION_ARG_NONE, nullptr, "Resume capture", nullptr},
        {"show-panel", 0, 0, G_OPTION_ARG_NONE, nullptr, "Show the control panel", nullptr},
        {"settings", 0, 0, G_OPTION_ARG_NONE, nullptr, "Open the settings window", nullptr},
        {"quit", 0, 0, G_OPTION_ARG_NONE, nullptr, "Quit the running instance", nullptr},
        {"version", 'v', 0, G_OPTION_ARG_NONE, nullptr, "Print the version and exit", nullptr},
        {nullptr},
    };
    g_application_add_main_option_entries(G_APPLICATION(gtk_app), entries);
    g_application_set_option_context_summary(G_APPLICATION(gtk_app),
        "Share one window that follows the window you are working in.\n"
        "With no options, starts CursorFollow (or raises the panel of the running instance).");

    g_signal_connect(gtk_app, "startup", G_CALLBACK(on_startup), nullptr);
    g_signal_connect(gtk_app, "activate", G_CALLBACK(on_activate), nullptr);
    g_signal_connect(gtk_app, "shutdown", G_CALLBACK(on_shutdown), nullptr);
    g_signal_connect(gtk_app, "command-line", G_CALLBACK(on_command_line), nullptr);
    g_signal_connect(gtk_app, "handle-local-options", G_CALLBACK(on_handle_local_options), nullptr);

    int status = g_application_run(G_APPLICATION(gtk_app), argc, argv);
    g_object_unref(gtk_app);
    return status;
}
