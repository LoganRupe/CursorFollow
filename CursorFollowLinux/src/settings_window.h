#pragma once

typedef struct _GtkWindow GtkWindow;

namespace cf {

class App;

/// Opens the settings window (one at a time) as a transient of `parent`.
/// Every control applies immediately; there is no Save step.
void show_settings_window(GtkWindow* parent, App& app);

}  // namespace cf
