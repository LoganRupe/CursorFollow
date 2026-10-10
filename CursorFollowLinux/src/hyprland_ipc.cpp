#include "hyprland_ipc.h"

#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <glib.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>

namespace cf {

namespace {

std::string join(const std::string& a, const std::string& b) {
    gchar* p = g_build_filename(a.c_str(), b.c_str(), nullptr);
    std::string s(p);
    g_free(p);
    return s;
}

}  // namespace

HyprlandIpc::HyprlandIpc() = default;

HyprlandIpc::~HyprlandIpc() {
    stop_events();
}

std::string HyprlandIpc::socket_dir() {
    const char* sig = g_getenv("HYPRLAND_INSTANCE_SIGNATURE");
    const char* runtime = g_get_user_runtime_dir();
    if (!sig || !*sig || !runtime) return {};
    return join(join(runtime, "hypr"), sig);
}

bool HyprlandIpc::available() {
    const std::string dir = socket_dir();
    return !dir.empty() && g_file_test(join(dir, ".socket.sock").c_str(), G_FILE_TEST_EXISTS);
}

std::optional<std::string> HyprlandIpc::request(const std::string& command, std::string* error) {
    const std::string dir = socket_dir();
    if (dir.empty()) {
        if (error) *error = "HYPRLAND_INSTANCE_SIGNATURE is not set; is this a Hyprland session?";
        return std::nullopt;
    }
    const std::string path = join(dir, ".socket.sock");

    int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        if (error) *error = std::string("socket(): ") + std::strerror(errno);
        return std::nullopt;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);
    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof addr) != 0) {
        if (error) *error = "connect(" + path + "): " + std::strerror(errno);
        ::close(fd);
        return std::nullopt;
    }

    const char* p = command.data();
    size_t left = command.size();
    while (left > 0) {
        ssize_t n = ::write(fd, p, left);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (error) *error = std::string("write(): ") + std::strerror(errno);
            ::close(fd);
            return std::nullopt;
        }
        p += n;
        left -= static_cast<size_t>(n);
    }

    std::string reply;
    char buf[8192];
    for (;;) {
        ssize_t n = ::read(fd, buf, sizeof buf);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (error) *error = std::string("read(): ") + std::strerror(errno);
            ::close(fd);
            return std::nullopt;
        }
        if (n == 0) break;
        reply.append(buf, static_cast<size_t>(n));
    }
    ::close(fd);
    return reply;
}

bool HyprlandIpc::dispatch(const std::string& lua, const std::string& legacy, std::string* error) {
    std::string err;
    auto reply = request("dispatch " + lua, &err);
    if (reply && *reply == "ok") return true;
    std::string first = reply ? *reply : err;
    reply = request("dispatch " + legacy, &err);
    if (reply && *reply == "ok") return true;
    if (error) *error = "dispatch failed: lua=" + first + "; legacy=" + (reply ? *reply : err);
    return false;
}

bool HyprlandIpc::start_events(EventHandler handler) {
    if (source_) return true;
    const std::string dir = socket_dir();
    if (dir.empty()) return false;

    GError* err = nullptr;
    socket_ = g_socket_new(G_SOCKET_FAMILY_UNIX, G_SOCKET_TYPE_STREAM, G_SOCKET_PROTOCOL_DEFAULT, &err);
    if (!socket_) {
        g_warning("Hyprland IPC: socket creation failed: %s", err ? err->message : "?");
        g_clear_error(&err);
        return false;
    }
    GSocketAddress* addr = g_unix_socket_address_new(join(dir, ".socket2.sock").c_str());
    gboolean ok = g_socket_connect(socket_, addr, nullptr, &err);
    g_object_unref(addr);
    if (!ok) {
        g_warning("Hyprland IPC: connect to event socket failed: %s", err ? err->message : "?");
        g_clear_error(&err);
        g_clear_object(&socket_);
        return false;
    }
    g_socket_set_blocking(socket_, FALSE);

    handler_ = std::move(handler);
    source_ = g_socket_create_source(socket_, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP | G_IO_ERR), nullptr);
    g_source_set_callback(source_, G_SOURCE_FUNC(&HyprlandIpc::on_readable), this, nullptr);
    g_source_attach(source_, nullptr);
    g_message("Hyprland IPC: listening for window events");
    return true;
}

void HyprlandIpc::stop_events() {
    if (source_) {
        g_source_destroy(source_);
        g_source_unref(source_);
        source_ = nullptr;
    }
    if (socket_) {
        g_socket_close(socket_, nullptr);
        g_clear_object(&socket_);
    }
    pending_.clear();
}

int HyprlandIpc::on_readable(GSocket* socket, int condition, void* user_data) {
    auto* self = static_cast<HyprlandIpc*>(user_data);
    if (condition & (G_IO_HUP | G_IO_ERR)) {
        g_warning("Hyprland IPC: event socket closed");
        self->stop_events();
        return G_SOURCE_REMOVE;
    }
    char buf[4096];
    for (;;) {
        GError* err = nullptr;
        gssize n = g_socket_receive(socket, buf, sizeof buf, nullptr, &err);
        if (n > 0) {
            self->pending_.append(buf, static_cast<size_t>(n));
            continue;
        }
        if (n == 0) {
            g_clear_error(&err);
            g_warning("Hyprland IPC: event socket EOF");
            self->stop_events();
            return G_SOURCE_REMOVE;
        }
        bool would_block = err && g_error_matches(err, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK);
        g_clear_error(&err);
        if (!would_block) {
            self->stop_events();
            return G_SOURCE_REMOVE;
        }
        break;
    }
    self->drain_lines();
    return G_SOURCE_CONTINUE;
}

void HyprlandIpc::drain_lines() {
    size_t start = 0;
    for (;;) {
        size_t nl = pending_.find('\n', start);
        if (nl == std::string::npos) break;
        std::string line = pending_.substr(start, nl - start);
        start = nl + 1;
        size_t sep = line.find(">>");
        if (sep == std::string::npos) continue;
        if (handler_) handler_(line.substr(0, sep), line.substr(sep + 2));
        if (!source_) return;  // handler stopped us
    }
    pending_.erase(0, start);
}

}  // namespace cf
