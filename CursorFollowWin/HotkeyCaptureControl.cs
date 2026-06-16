using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using System.Runtime.InteropServices;
using Windows.System;

namespace CursorFollowWin;

/// <summary>
/// A settings control that records a global hotkey. Click to enter capture mode, then press
/// the desired modifier + key combination. Escape or losing focus cancels the capture.
/// </summary>
internal sealed class HotkeyCaptureControl : Button
{
    private const int VkShift = 0x10;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;
    private const int VkLeftWin = 0x5B;
    private const int VkRightWin = 0x5C;
    private const short KeyDownMask = unchecked((short)0x8000);

    private static readonly SolidColorBrush TransparentBrush = new(Windows.UI.Color.FromArgb(0, 0, 0, 0));
    private static readonly SolidColorBrush WhiteBrush = new(Windows.UI.Color.FromArgb(255, 255, 255, 255));
    private static readonly SolidColorBrush MutedBrush = new(Windows.UI.Color.FromArgb(255, 174, 184, 200));
    private static readonly SolidColorBrush CapBrush = new(Windows.UI.Color.FromArgb(255, 56, 60, 78));
    private static readonly SolidColorBrush CapturingBrush = new(Windows.UI.Color.FromArgb(255, 32, 111, 230));

    private Hotkey _value = Hotkey.None;
    private bool _capturing;

    public HotkeyCaptureControl()
    {
        Background = TransparentBrush;
        BorderThickness = new Thickness(0);
        Padding = new Thickness(2);
        MinWidth = 96;
        VerticalAlignment = VerticalAlignment.Center;
        HorizontalAlignment = HorizontalAlignment.Right;

        Click += OnClick;
        KeyDown += OnKeyDown;
        LostFocus += (_, _) => EndCapture();
        UpdateContent();
    }

    public Hotkey Value
    {
        get => _value;
        set
        {
            _value = value;
            if (!_capturing)
            {
                UpdateContent();
            }
        }
    }

    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (_capturing)
        {
            EndCapture();
            return;
        }

        _capturing = true;
        Content = CreatePrompt("Press shortcut…", CapturingBrush);
        Focus(FocusState.Programmatic);
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (!_capturing)
        {
            return;
        }

        // Swallow keys while capturing so Space/Enter don't re-trigger the button.
        e.Handled = true;

        if (e.Key == VirtualKey.Escape)
        {
            EndCapture();
            return;
        }

        if (IsModifierKey(e.Key))
        {
            return;
        }

        var modifiers = CurrentModifiers();
        if (modifiers == HotkeyModifiers.None)
        {
            // A global hotkey needs at least one modifier; keep listening.
            return;
        }

        var candidate = new Hotkey(modifiers, (uint)e.Key);
        if (!candidate.IsValid)
        {
            return;
        }

        _value = candidate;
        EndCapture();
    }

    private void EndCapture()
    {
        _capturing = false;
        UpdateContent();
    }

    private void UpdateContent()
    {
        Content = _value.IsValid
            ? CreateCaps(_value.ToDisplayParts())
            : CreatePrompt("Set shortcut", MutedBrush);
    }

    private static UIElement CreateCaps(IReadOnlyList<string> parts)
    {
        var panel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            HorizontalAlignment = HorizontalAlignment.Right,
        };

        foreach (var part in parts)
        {
            panel.Children.Add(new Border
            {
                MinWidth = 30,
                Height = 26,
                Padding = new Thickness(7, 0, 7, 0),
                Background = CapBrush,
                CornerRadius = new CornerRadius(6),
                Child = new TextBlock
                {
                    Text = part,
                    Foreground = WhiteBrush,
                    FontSize = 12,
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            });
        }

        return panel;
    }

    private static TextBlock CreatePrompt(string text, Brush foreground) => new()
    {
        Text = text,
        Foreground = foreground,
        FontSize = 13,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static bool IsModifierKey(VirtualKey key) => key is
        VirtualKey.Control or VirtualKey.LeftControl or VirtualKey.RightControl or
        VirtualKey.Shift or VirtualKey.LeftShift or VirtualKey.RightShift or
        VirtualKey.Menu or VirtualKey.LeftMenu or VirtualKey.RightMenu or
        VirtualKey.LeftWindows or VirtualKey.RightWindows;

    private static HotkeyModifiers CurrentModifiers()
    {
        var modifiers = HotkeyModifiers.None;
        if (IsKeyDown(VkControl))
        {
            modifiers |= HotkeyModifiers.Control;
        }

        if (IsKeyDown(VkMenu))
        {
            modifiers |= HotkeyModifiers.Alt;
        }

        if (IsKeyDown(VkShift))
        {
            modifiers |= HotkeyModifiers.Shift;
        }

        if (IsKeyDown(VkLeftWin) || IsKeyDown(VkRightWin))
        {
            modifiers |= HotkeyModifiers.Win;
        }

        return modifiers;
    }

    private static bool IsKeyDown(int virtualKey) => (GetKeyState(virtualKey) & KeyDownMask) != 0;

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int nVirtKey);
}
