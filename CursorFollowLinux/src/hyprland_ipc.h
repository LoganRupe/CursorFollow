#pragma once

#include <functional>
#include <optional>
#include <string>

typedef struct _GSocket GSocket;
typedef struct _GSource GSource;

namespace cf {

/// Thin client for Hyprland's two IPC sockets: `.socket.sock` for request/response
/// (`hyprctl` without the binary) and `.socket2.sock` for the event stream.
/// Everything runs on the GLib main loop; no threads.
class HyprlandIpc {
public:
    using EventHandler = std::function<void(const std::string& name, const std::string& data)>;

    HyprlandIpc();
    ~HyprlandIpc();

    HyprlandIpc(const HyprlandIpc&) = delete;
    HyprlandIpc& operator=(const HyprlandIpc&) = delete;

    /// True when HYPRLAND_INSTANCE_SIGNATURE points at a live socket directory.
    static bool available();
    static std::string socket_dir();

    /// One request, one connection, whole reply. `j/clients`, `dispatch ...` and so on.
    std::optional<std::string> request(const std::string& command, std::string* error = nullptr);

    /// Runs `hl.dispatch(...)`-style Lua first (Hyprland 0.5x) and falls back to the
    /// classic dispatcher syntax, the same way Omarchy's helper scripts do.
    bool dispatch(const std::string& lua, const std::string& legacy, std::string* error = nullptr);

    bool start_events(EventHandler handler);
    void stop_events();
    bool events_running() const { return source_ != nullptr; }

private:
    static int on_readable(GSocket* socket, int condition, void* user_data);
    void drain_lines();

    EventHandler handler_;
    GSocket* socket_ = nullptr;
    GSource* source_ = nullptr;
    std::string pending_;
};

}  // namespace cf
