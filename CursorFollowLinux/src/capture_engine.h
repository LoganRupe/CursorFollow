#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "app_settings.h"
#include "tracked_window.h"

typedef struct _GdkDisplay GdkDisplay;
typedef struct _GdkTexture GdkTexture;
struct wl_display;
struct wl_registry;
struct wl_shm;
struct wl_shm_pool;
struct wl_buffer;
struct hyprland_toplevel_export_manager_v1;
struct hyprland_toplevel_export_frame_v1;

namespace cf {

/// Captures one Hyprland toplevel through hyprland_toplevel_export_v1 and hands each
/// frame to the output window as a GdkTexture. Frames land in wl_shm buffers that are
/// wrapped (not copied) into GdkMemoryTexture; a buffer goes back into the pool when
/// GTK drops the texture. Everything runs on the GTK main loop, which also dispatches
/// the Wayland events because the engine shares GDK's wl_display connection.
class CaptureEngine {
public:
    explicit CaptureEngine(AppSettings& settings);
    ~CaptureEngine();

    CaptureEngine(const CaptureEngine&) = delete;
    CaptureEngine& operator=(const CaptureEngine&) = delete;

    /// Binds the Wayland globals on GDK's display. False when the compositor does not
    /// offer hyprland_toplevel_export_v1; error() then explains.
    bool init(GdkDisplay* display);
    const std::string& error() const { return error_; }
    bool supported() const { return manager_ != nullptr; }

    void start(const TrackedWindow& window);
    void stop();
    /// User-initiated stop: also blocks auto-follow from restarting capture.
    void user_stop();
    void clear_user_stopped() { user_stopped_ = false; }
    void switch_target(const TrackedWindow& window);

    bool is_capturing() const { return capturing_; }
    bool user_stopped() const { return user_stopped_; }
    uint64_t frame_count() const { return frame_count_; }
    int capture_width() const { return capture_width_; }
    int capture_height() const { return capture_height_; }
    const std::optional<TrackedWindow>& target() const { return target_; }
    const std::optional<std::string>& last_error() const { return last_error_; }

    CaptureQuality quality() const { return quality_; }
    void set_quality(CaptureQuality quality);

    /// A new frame. The texture is owned by the engine for the duration of the call;
    /// keep a reference if it must outlive it.
    std::function<void(GdkTexture* texture, int width, int height)> on_frame;
    /// Capture start/stop transitions and capture-size changes.
    std::function<void()> on_state_changed;
    /// The compositor refused or lost the target.
    std::function<void(const std::string& message)> on_error;

private:
    struct ShmBuffer;
    struct FrameContext;

    void request_frame();
    void schedule_next_frame(unsigned delay_ms);
    void cancel_timer();
    void destroy_frame();
    void fail_frame(const char* why);
    ShmBuffer* acquire_buffer(uint32_t format, uint32_t width, uint32_t height, uint32_t stride);
    void release_buffer(ShmBuffer* buffer);
    void publish(ShmBuffer* buffer, bool y_invert);
    void set_capturing(bool capturing);

    static void registry_global(void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version);
    static void registry_global_remove(void* data, wl_registry* registry, uint32_t name);
    static void frame_buffer(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t format, uint32_t width, uint32_t height, uint32_t stride);
    static void frame_damage(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t x, uint32_t y, uint32_t width, uint32_t height);
    static void frame_flags(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t flags);
    static void frame_ready(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t tv_sec_hi, uint32_t tv_sec_lo, uint32_t tv_nsec);
    static void frame_failed(void* data, hyprland_toplevel_export_frame_v1* frame);
    static void frame_linux_dmabuf(void* data, hyprland_toplevel_export_frame_v1* frame, uint32_t format, uint32_t width, uint32_t height);
    static void frame_buffer_done(void* data, hyprland_toplevel_export_frame_v1* frame);
    static int on_timer(void* user_data);
    static void on_texture_released(void* user_data);

    AppSettings& settings_;
    wl_display* display_ = nullptr;
    wl_registry* registry_ = nullptr;
    wl_shm* shm_ = nullptr;
    hyprland_toplevel_export_manager_v1* manager_ = nullptr;
    std::string error_;

    std::vector<std::unique_ptr<ShmBuffer>> buffers_;
    std::unique_ptr<FrameContext> frame_;
    unsigned timer_ = 0;
    int64_t last_request_us_ = 0;
    bool first_frame_ = true;
    int consecutive_failures_ = 0;

    std::optional<TrackedWindow> target_;
    std::optional<std::string> last_error_;
    bool capturing_ = false;
    bool user_stopped_ = true;
    uint64_t frame_count_ = 0;
    int capture_width_ = 0;
    int capture_height_ = 0;
    CaptureQuality quality_ = CaptureQuality::Balanced;
};

}  // namespace cf
