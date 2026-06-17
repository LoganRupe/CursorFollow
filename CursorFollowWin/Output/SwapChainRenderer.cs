using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Windows.Graphics;
using Windows.Graphics.DirectX.Direct3D11;

namespace CursorFollowWin;

/// <summary>
/// Renders captured GPU surfaces straight onto a <see cref="CanvasSwapChainPanel"/> with no CPU
/// readback. The swap chain shares the capture controller's <see cref="CanvasDevice"/>, so a captured
/// frame is drawn by wrapping it as a <see cref="CanvasBitmap"/> and presenting — the path that
/// replaces the old ~60&#160;ms <c>SoftwareBitmap.CreateCopyFromSurfaceAsync</c> copy.
/// </summary>
internal sealed class SwapChainRenderer : IDisposable
{
    private const float Dpi = 96f; // size the swap chain in raw pixels; the Viewbox handles display scaling

    private readonly CanvasSwapChainPanel _panel;
    private readonly CanvasDevice _device;
    private readonly object _gate = new();

    private CanvasSwapChain? _swapChain;
    private SizeInt32 _size;
    private bool _disposed;

    public SwapChainRenderer(CanvasSwapChainPanel panel, CanvasDevice device)
    {
        _panel = panel;
        _device = device;
    }

    /// <summary>
    /// Draws the live capture surface and presents. Called synchronously on the capture thread while
    /// the surface is still valid. Serialized so a resize cannot race a draw.
    /// </summary>
    public void Render(IDirect3DSurface surface, SizeInt32 size)
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            EnsureSwapChain(size);
            using var bitmap = CanvasBitmap.CreateFromDirect3D11Surface(_device, surface);
            using (var session = _swapChain!.CreateDrawingSession(Microsoft.UI.Colors.Black))
            {
                session.DrawImage(bitmap);
            }

            _swapChain.Present();
        }
    }

    /// <summary>Presents a black frame so a stopped/idle output does not freeze on the last image.</summary>
    public void Clear()
    {
        lock (_gate)
        {
            if (_disposed || _swapChain is null)
            {
                return;
            }

            using (_swapChain.CreateDrawingSession(Microsoft.UI.Colors.Black))
            {
            }

            _swapChain.Present();
        }
    }

    private void EnsureSwapChain(SizeInt32 size)
    {
        if (_swapChain is null)
        {
            _swapChain = new CanvasSwapChain(_device, size.Width, size.Height, Dpi);
            _size = size;

            // The panel association must happen on the UI thread; rendering/Present stays on the
            // capture thread, which Win2D swap chains support.
            var swapChain = _swapChain;
            _panel.DispatcherQueue.TryEnqueue(() =>
            {
                if (!_disposed)
                {
                    _panel.SwapChain = swapChain;
                }
            });
        }
        else if (size.Width != _size.Width || size.Height != _size.Height)
        {
            _swapChain.ResizeBuffers(size.Width, size.Height, Dpi);
            _size = size;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _swapChain?.Dispose();
            _swapChain = null;
        }
    }
}
