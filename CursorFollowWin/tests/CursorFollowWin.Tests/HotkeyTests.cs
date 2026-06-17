using Xunit;

namespace CursorFollowWin.Tests;

public class HotkeyTests
{
    private const uint VkF = 0x46; // 'F'
    private const uint VkF5 = 0x74;

    [Fact]
    public void Parse_ModifiersAndKey_RoundTripsThroughFormat()
    {
        var hotkey = Hotkey.Parse("Ctrl+Alt+F");

        Assert.True(hotkey.IsValid);
        Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Alt, hotkey.Modifiers);
        Assert.Equal(VkF, hotkey.VirtualKey);
        Assert.Equal("Ctrl+Alt+F", hotkey.Format());
    }

    [Fact]
    public void Parse_MacOptionModifier_MapsToWindowsAlt()
    {
        // "Opt"/"Option" are macOS spellings; on Windows they must register as Alt, not be dropped.
        var fromOpt = Hotkey.Parse("Opt+F");
        var fromOption = Hotkey.Parse("Option+F");

        Assert.Equal(HotkeyModifiers.Alt, fromOpt.Modifiers);
        Assert.Equal(HotkeyModifiers.Alt, fromOption.Modifiers);
        Assert.Equal("Alt+F", fromOpt.Format());
    }

    [Fact]
    public void Parse_FunctionKey_IsRecognized()
    {
        var hotkey = Hotkey.Parse("Ctrl+Shift+F5");

        Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Shift, hotkey.Modifiers);
        Assert.Equal(VkF5, hotkey.VirtualKey);
        Assert.Equal("Ctrl+Shift+F5", hotkey.Format());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Parse_BlankInput_ReturnsNone(string? text)
    {
        var hotkey = Hotkey.Parse(text);

        Assert.Equal(Hotkey.None, hotkey);
        Assert.False(hotkey.IsValid);
        Assert.Equal(string.Empty, hotkey.Format());
    }

    [Fact]
    public void IsValid_RequiresBothModifierAndKey()
    {
        Assert.False(Hotkey.Parse("F").IsValid);     // key, no modifier
        Assert.False(Hotkey.Parse("Ctrl").IsValid);  // modifier, no key
        Assert.True(Hotkey.Parse("Ctrl+F").IsValid);
    }

    [Fact]
    public void Parse_IsCaseInsensitive()
    {
        Assert.Equal(Hotkey.Parse("Ctrl+Alt+F"), Hotkey.Parse("ctrl+alt+f"));
    }
}
