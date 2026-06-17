namespace CursorFollowWin;

[Flags]
public enum HotkeyModifiers : uint
{
    None = 0,
    Alt = 0x1,       // MOD_ALT
    Control = 0x2,   // MOD_CONTROL
    Shift = 0x4,     // MOD_SHIFT
    Win = 0x8,       // MOD_WIN
}

/// <summary>
/// A global hotkey expressed as a set of modifiers plus a Win32 virtual-key code.
/// The modifier values match the <c>MOD_*</c> flags expected by <c>RegisterHotKey</c>.
/// </summary>
public readonly record struct Hotkey(HotkeyModifiers Modifiers, uint VirtualKey)
{
    public static readonly Hotkey None = new(HotkeyModifiers.None, 0);

    /// <summary>A hotkey is only registerable if it has a key and at least one modifier.</summary>
    public bool IsValid => VirtualKey != 0 && Modifiers != HotkeyModifiers.None;

    public IReadOnlyList<string> ToDisplayParts()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotkeyModifiers.Control))
        {
            parts.Add("Ctrl");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            parts.Add("Alt");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            parts.Add("Shift");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Win))
        {
            parts.Add("Win");
        }

        var key = KeyName(VirtualKey);
        if (key.Length > 0)
        {
            parts.Add(key);
        }

        return parts;
    }

    /// <summary>Stable round-trippable text form such as <c>Ctrl+Alt+F</c>.</summary>
    public string Format() => IsValid ? string.Join("+", ToDisplayParts()) : string.Empty;

    public override string ToString() => Format();

    public static Hotkey Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return None;
        }

        var modifiers = HotkeyModifiers.None;
        uint virtualKey = 0;

        foreach (var token in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (token.ToLowerInvariant())
            {
                case "ctrl":
                case "control":
                    modifiers |= HotkeyModifiers.Control;
                    break;
                case "alt":
                case "opt":
                case "option":
                    modifiers |= HotkeyModifiers.Alt;
                    break;
                case "shift":
                    modifiers |= HotkeyModifiers.Shift;
                    break;
                case "win":
                case "cmd":
                case "super":
                    modifiers |= HotkeyModifiers.Win;
                    break;
                default:
                    virtualKey = KeyCode(token);
                    break;
            }
        }

        return new Hotkey(modifiers, virtualKey);
    }

    private static string KeyName(uint virtualKey) => virtualKey switch
    {
        >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(), // A-Z
        >= 0x30 and <= 0x39 => ((char)virtualKey).ToString(), // 0-9
        >= 0x70 and <= 0x87 => "F" + (virtualKey - 0x6F),      // F1-F24
        0x20 => "Space",
        _ => string.Empty,
    };

    private static uint KeyCode(string token)
    {
        if (token.Length == 1)
        {
            var upper = char.ToUpperInvariant(token[0]);
            if (upper is >= 'A' and <= 'Z' or >= '0' and <= '9')
            {
                return upper;
            }
        }

        if (string.Equals(token, "Space", StringComparison.OrdinalIgnoreCase))
        {
            return 0x20;
        }

        if (token.Length > 1
            && token[0] is 'f' or 'F'
            && int.TryParse(token.AsSpan(1), out var number)
            && number is >= 1 and <= 24)
        {
            return (uint)(0x6F + number);
        }

        return 0;
    }
}
