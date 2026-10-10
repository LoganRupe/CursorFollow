#define _GNU_SOURCE 1
#include "capture_engine.h"

#include <gdk/gdk.h>
#include <gdk/wayland/gdkwayland.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include <algorithm>
#include <cerrno>
#include <cstring>

#include "hyprland-toplevel-export-v1-client.h"

namespace cf {

namespace {

constexpr size_t kMaxBuffers = 6;
constexpr int kMaxConsecutiveFailures = 3;

bool gdk_format_for_shm(uint32_t shm_format, GdkMemoryFormat& out) {
    switch (shm_format) {
        case WL_SHM_FORMAT_ARGB8888: out = GDK_MEMORY_B8G8R8A8_PREMULTIPLIED; return true;
        case WL_SHM_FORMAT_XRGB8888: out = GDK_MEMORY_B8G8R8X8; return true;
        case WL_SHM_FORMAT_ABGR8888: out = GDK_MEMORY_R8G8B8A8_PREMULTIPLIED; return true;
        case WL_SHM_FORMAT_XBGR8888: out = GDK_MEMORY_R8G8B8X8; return true;
        default: return false;
    }
}

}  // namespace

/// One wl_shm buffer plus the memory behind it. `in_use` covers both "the compositor
/// is writing into it" and "a GdkTexture still references it".
struct CaptureEngine::ShmBuffer {
    CaptureEngine* owner = nullptr;
    int fd = -1;
    void* data = nullptr;
    size_t size = 0;
    wl_shm_pool* pool = nullptr;
    wl_buffer* buffer = nullptr;
    uint32_t format = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t stride = 0;
    bool in_use = false;
    bool orphaned = false;  // engine dropped it while a texture still held it

    ~ShmBuffer() {
        if (buffer) wl_buffer_destroy(buffer);
        if (pool) wl_shm_pool_destroy(pool);
        if (data) munmap(data, size);
        if (fd >= 0) close(fd);
    }
};

/// State for the one frame request in flight.
struct CaptureEngine::FrameContext {
    hyprland_toplevel_export_frame_v1* frame = nullptr;
    uint32_t format = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t stride = 0;
    bool have_shm = false;
    bool y_invert = false;
    ShmBuffer* buffer = nullptr;

    ~FrameContext() {
        if (frame) hyprland_toplevel_export_frame_v1_destroy(frame);
    }
};

CaptureEngine::CaptureEngine(AppSettings& settings) : settings_(settings), quality_(settings.capture_quality()) {}

CaptureEngine::~CaptureEngine() {
    stop();
    for (auto& b : buffers_) {
        if (b->in_use) {
            // A texture still points at the memory; let the release callback free it.
            b->orphaned = true;
            b.release();
        }
    }
    buffers_.clear();
    if (manager_) hyprland_toplevel_export_manager_v1_destroy(manager_);
    if (shm_) wl_shm_destroy(shm_);
    if (registry_) wl_registry_destroy(registry_);
}

bool CaptureEngine::init(GdkDisplay* display) {
    if (!GDK_IS_WAYLAND_DISPLAY(display)) {
        error_ = "CursorFollow needs a Wayland session (GDK is not using the Wayland backend).";
        return false;
    }
    display_ = gdk_wayland_display_get_wl_display(GDK_WAYLAND_DISPLAY(display));
    registry_ = wl_display_get_registry(display_);
    static const wl_registry_listener listener = {
        &CaptureEngine::registry_global,
        &CaptureEngine::registry_global_remove,
    };
    wl_registry_add_listener(registry_, &listener, this);
    wl_display_roundtrip(display_);

    if (!shm_) {
        error_ = "The compositor does not offer wl_shm.";
        return false;
    }
    if (!manager_) {
        error_ = "The compositor does not offer hyprland_toplevel_export_v1. "
                 "Per-window capture currently needs Hyprland.";
        return false;
    }
    g_message("Capture: hyprland_toplevel_export_v1 bound");
    return true;
}

void CaptureEngine::registry_global(void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (std::strcmp(interface, hyprland_toplevel_export_manager_v1_interface.name) == 0) {
        self->manager_ = static_cast<hyprland_toplevel_export_manager_v1*>(
            wl_registry_bind(registry, name, &hyprland_toplevel_export_manager_v1_interface, std::min<uint32_t>(version, 2)));
    } else if (std::strcmp(interface, wl_shm_interface.name) == 0) {
        self->shm_ = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
    }
}

void CaptureEngine::registry_global_remove(void*, wl_registry*, uint32_t) {}

void CaptureEngine::set_quality(CaptureQuality quality) {
    quality_ = quality;
    settings_.set_capture_quality(quality);
    // Takes effect at the next frame request; nothing to restart.
}

void CaptureEngine::start(const TrackedWindow& window) {
    user_stopped_ = false;
    if (!manager_) {
        last_error_ = error_.empty() ? "Capture is not available." : error_;
        if (on_error) on_error(*last_error_);
        return;
    }
    if (capturing_) {
        g_message("Capture already running; switching target");
        stop();
    }
    target_ = window;
    last_error_.reset();
    frame_count_ = 0;
    first_frame_ = true;
    consecutive_failures_ = 0;
    capture_width_ = window.width;
    capture_height_ = window.height;
    set_capturing(true);
    g_message("Capture started for '%s' (%s), max %d fps", window.title.c_str(), window.address_hex().c_str(),
              capture_quality_max_fps(quality_));
    request_frame();
}

void CaptureEngine::stop() {
    cancel_timer();
    destroy_frame();
    if (!capturing_) return;
    g_message("Capture stopped after %llu frames", static_cast<unsigned long long>(frame_count_));
    set_capturing(false);
}

void CaptureEngine::user_stop() {
    user_stopped_ = true;
    stop();
}

void CaptureEngine::switch_target(const TrackedWindow& window) {
    stop();
    start(window);
}

void CaptureEngine::set_capturing(bool capturing) {
    if (capturing_ == capturing) return;
    capturing_ = capturing;
    if (on_state_changed) on_state_changed();
}

void CaptureEngine::cancel_timer() {
    if (timer_) {
        g_source_remove(timer_);
        timer_ = 0;
    }
}

void CaptureEngine::destroy_frame() {
    if (frame_ && frame_->buffer) {
        // The compositor never delivered; the buffer is free again.
        frame_->buffer->in_use = false;
    }
    frame_.reset();
}

void CaptureEngine::request_frame() {
    if (!capturing_ || !target_ || frame_) return;
    frame_ = std::make_unique<FrameContext>();
    frame_->frame = hyprland_toplevel_export_manager_v1_capture_toplevel(manager_, 1, target_->export_handle());
    static const hyprland_toplevel_export_frame_v1_listener listener = {
        &CaptureEngine::frame_buffer,
        &CaptureEngine::frame_damage,
        &CaptureEngine::frame_flags,
        &CaptureEngine::frame_ready,
        &CaptureEngine::frame_failed,
        &CaptureEngine::frame_linux_dmabuf,
        &CaptureEngine::frame_buffer_done,
    };
    hyprland_toplevel_export_frame_v1_add_listener(frame_->frame, &listener, this);
    last_request_us_ = g_get_monotonic_time();
    wl_display_flush(display_);
}

void CaptureEngine::schedule_next_frame(unsigned delay_ms) {
    cancel_timer();
    if (!capturing_) return;
    timer_ = g_timeout_add(delay_ms, &CaptureEngine::on_timer, this);
}

int CaptureEngine::on_timer(void* user_data) {
    auto* self = static_cast<CaptureEngine*>(user_data);
    self->timer_ = 0;
    self->request_frame();
    return G_SOURCE_REMOVE;
}

void CaptureEngine::frame_buffer(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t format, uint32_t width, uint32_t height, uint32_t stride) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (!self->frame_ || self->frame_->frame != frame) return;
    self->frame_->format = format;
    self->frame_->width = width;
    self->frame_->height = height;
    self->frame_->stride = stride;
    self->frame_->have_shm = true;
}

void CaptureEngine::frame_linux_dmabuf(void*, hyprland_toplevel_export_frame_v1*, uint32_t, uint32_t, uint32_t) {
    // dmabuf transport is a later optimisation; shm is always offered.
}

void CaptureEngine::frame_damage(void*, hyprland_toplevel_export_frame_v1*, uint32_t, uint32_t, uint32_t, uint32_t) {}

void CaptureEngine::frame_flags(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t flags) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (!self->frame_ || self->frame_->frame != frame) return;
    self->frame_->y_invert = (flags & HYPRLAND_TOPLEVEL_EXPORT_FRAME_V1_FLAGS_Y_INVERT) != 0;
}

void CaptureEngine::frame_buffer_done(void* data, hyprland_toplevel_export_frame_v1* frame) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (!self->frame_ || self->frame_->frame != frame) return;
    FrameContext& ctx = *self->frame_;
    if (!ctx.have_shm || ctx.width == 0 || ctx.height == 0) {
        self->fail_frame("compositor offered no shm buffer");
        return;
    }
    GdkMemoryFormat unused;
    if (!gdk_format_for_shm(ctx.format, unused)) {
        char msg[96];
        std::snprintf(msg, sizeof msg, "unsupported pixel format 0x%08x", ctx.format);
        self->fail_frame(msg);
        return;
    }
    ShmBuffer* buffer = self->acquire_buffer(ctx.format, ctx.width, ctx.height, ctx.stride);
    if (!buffer) {
        // Every buffer is still referenced by a texture; try again shortly.
        self->destroy_frame();
        self->schedule_next_frame(8);
        return;
    }
    ctx.buffer = buffer;
    buffer->in_use = true;
    // The first frame after a (re)start must not wait for damage, or a static window
    // would never show up. Later frames wait, which keeps idle CPU near zero.
    hyprland_toplevel_export_frame_v1_copy(frame, buffer->buffer, self->first_frame_ ? 1 : 0);
    wl_display_flush(self->display_);
}

void CaptureEngine::frame_ready(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t, uint32_t, uint32_t) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (!self->frame_ || self->frame_->frame != frame) return;
    ShmBuffer* buffer = self->frame_->buffer;
    bool y_invert = self->frame_->y_invert;
    self->frame_.reset();  // destroys the protocol object
    self->first_frame_ = false;
    self->consecutive_failures_ = 0;
    if (buffer) self->publish(buffer, y_invert);

    const int64_t interval_us = 1000000 / std::max(1, capture_quality_max_fps(self->quality_));
    const int64_t elapsed_us = g_get_monotonic_time() - self->last_request_us_;
    const int64_t wait_us = std::max<int64_t>(0, interval_us - elapsed_us);
    self->schedule_next_frame(static_cast<unsigned>(wait_us / 1000));
}

void CaptureEngine::frame_failed(void* data, hyprland_toplevel_export_frame_v1* frame) {
    auto* self = static_cast<CaptureEngine*>(data);
    if (!self->frame_ || self->frame_->frame != frame) return;
    self->fail_frame("compositor reported the copy failed");
}

void CaptureEngine::fail_frame(const char* why) {
    destroy_frame();
    ++consecutive_failures_;
    g_warning("Capture frame failed (%d/%d): %s", consecutive_failures_, kMaxConsecutiveFailures, why);
    if (consecutive_failures_ >= kMaxConsecutiveFailures) {
        std::string title = target_ ? target_->title : "The target";
        last_error_ = title + " could not be captured (" + why + ").";
        cancel_timer();
        set_capturing(false);
        if (on_error) on_error(*last_error_);
        return;
    }
    schedule_next_frame(250);
}

CaptureEngine::ShmBuffer* CaptureEngine::acquire_buffer(uint32_t format, uint32_t width, uint32_t height, uint32_t stride) {
    // Drop free buffers that no longer match the target's size.
    buffers_.erase(std::remove_if(buffers_.begin(), buffers_.end(), [&](const std::unique_ptr<ShmBuffer>& b) {
        return !b->in_use && (b->format != format || b->width != width || b->height != height || b->stride != stride);
    }), buffers_.end());

    for (auto& b : buffers_) {
        if (!b->in_use) return b.get();
    }
    if (buffers_.size() >= kMaxBuffers) return nullptr;

    auto b = std::make_unique<ShmBuffer>();
    b->owner = this;
    b->format = format;
    b->width = width;
    b->height = height;
    b->stride = stride;
    b->size = static_cast<size_t>(stride) * height;
    b->fd = memfd_create("cursorfollow-frame", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (b->fd < 0 || ftruncate(b->fd, static_cast<off_t>(b->size)) != 0) {
        g_warning("Capture: memfd allocation failed: %s", std::strerror(errno));
        return nullptr;
    }
    b->data = mmap(nullptr, b->size, PROT_READ | PROT_WRITE, MAP_SHARED, b->fd, 0);
    if (b->data == MAP_FAILED) {
        b->data = nullptr;
        g_warning("Capture: mmap failed: %s", std::strerror(errno));
        return nullptr;
    }
    b->pool = wl_shm_create_pool(shm_, b->fd, static_cast<int32_t>(b->size));
    b->buffer = wl_shm_pool_create_buffer(b->pool, 0, static_cast<int32_t>(width), static_cast<int32_t>(height),
                                          static_cast<int32_t>(stride), format);
    ShmBuffer* raw = b.get();
    buffers_.push_back(std::move(b));
    g_debug("Capture: allocated buffer %ux%u stride %u (%zu in pool)", width, height, stride, buffers_.size());
    return raw;
}

void CaptureEngine::on_texture_released(void* user_data) {
    auto* buffer = static_cast<ShmBuffer*>(user_data);
    if (buffer->orphaned) {
        delete buffer;
        return;
    }
    buffer->in_use = false;
}

void CaptureEngine::release_buffer(ShmBuffer* buffer) {
    buffer->in_use = false;
}

void CaptureEngine::publish(ShmBuffer* buffer, bool y_invert) {
    if (y_invert) {
        // Rare on Hyprland; flip in place rather than teach the renderer about it.
        std::vector<uint8_t> tmp(buffer->stride);
        auto* base = static_cast<uint8_t*>(buffer->data);
        for (uint32_t top = 0, bottom = buffer->height - 1; top < bottom; ++top, --bottom) {
            uint8_t* a = base + static_cast<size_t>(top) * buffer->stride;
            uint8_t* b = base + static_cast<size_t>(bottom) * buffer->stride;
            std::memcpy(tmp.data(), a, buffer->stride);
            std::memcpy(a, b, buffer->stride);
            std::memcpy(b, tmp.data(), buffer->stride);
        }
    }

    GdkMemoryFormat format = GDK_MEMORY_B8G8R8A8_PREMULTIPLIED;
    gdk_format_for_shm(buffer->format, format);
    GBytes* bytes = g_bytes_new_with_free_func(buffer->data, buffer->size, &CaptureEngine::on_texture_released, buffer);
    GdkTexture* texture = gdk_memory_texture_new(static_cast<int>(buffer->width), static_cast<int>(buffer->height), format, bytes,
                                                 buffer->stride);
    g_bytes_unref(bytes);

    ++frame_count_;
    bool size_changed = capture_width_ != static_cast<int>(buffer->width) || capture_height_ != static_cast<int>(buffer->height);
    capture_width_ = static_cast<int>(buffer->width);
    capture_height_ = static_cast<int>(buffer->height);
    if (size_changed && on_state_changed) on_state_changed();
    if (frame_count_ % 300 == 0) {
        g_message("Capture: %llu frames delivered", static_cast<unsigned long long>(frame_count_));
    }
    if (on_frame) on_frame(texture, capture_width_, capture_height_);
    g_object_unref(texture);
}

}  // namespace cf
