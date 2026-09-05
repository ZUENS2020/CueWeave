using CueWeave.WinUI.Timeline;
using Windows.System;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class TimelineKeyboardTests
{
    [TestMethod]
    public void NextToggleIsAvailableOutsideEditorsAndOnlyRunsOncePerPress()
    {
        var keyboard = new TimelineKeyboard();
        Assert.IsFalse(TimelineKeyboard.IsReserved(VirtualKey.N, ShortcutOwner.Workspace));
        Assert.IsFalse(TimelineKeyboard.IsReserved(VirtualKey.N, ShortcutOwner.NativeControl));
        Assert.IsFalse(TimelineKeyboard.IsReserved(VirtualKey.C, ShortcutOwner.NativeControl));
        Assert.IsTrue(TimelineKeyboard.IsReserved(VirtualKey.N, ShortcutOwner.Editor));
        Assert.IsTrue(TimelineKeyboard.IsReserved(VirtualKey.C, ShortcutOwner.Editor));
        Assert.IsTrue(TimelineKeyboard.IsReserved(VirtualKey.N, ShortcutOwner.Modal));
        Assert.AreEqual(new TimelineKeyAction("toggle_follow_next"), keyboard.Translate(new(VirtualKey.N)));
        Assert.AreEqual(new TimelineKeyAction("toggle_follow_current"), keyboard.Translate(new(VirtualKey.C)));
        Assert.AreEqual(new TimelineKeyAction("consume"), keyboard.Translate(new(VirtualKey.C, Repeat: true)));
        Assert.AreEqual(new TimelineKeyAction("consume"), keyboard.Translate(new(VirtualKey.N, Repeat: true)));
        Assert.IsNull(keyboard.Translate(new(VirtualKey.N, Control: true)));
        Assert.IsNull(keyboard.Translate(new(VirtualKey.N, Alt: true)));
        Assert.IsNull(keyboard.Translate(new(VirtualKey.N, Shift: true)));
        Assert.IsNull(keyboard.Translate(new(VirtualKey.N, Released: true)));
        Assert.AreEqual(new TimelineKeyAction("toggle_follow_next"), keyboard.Translate(new(VirtualKey.N)));
    }

    [TestMethod]
    public void NativeControlsRetainNavigationAndTextEditorsRetainEveryKey()
    {
        foreach (var key in new[] { VirtualKey.Space, VirtualKey.Enter, VirtualKey.Tab, VirtualKey.Left, VirtualKey.Home })
            Assert.IsTrue(TimelineKeyboard.IsReserved(key, ShortcutOwner.NativeControl));
        foreach (var key in Enum.GetValues<VirtualKey>())
            Assert.IsTrue(TimelineKeyboard.IsReserved(key, ShortcutOwner.Editor));
    }

    [TestMethod]
    public void SelectionAndPlaybackCommandsMatchMac()
    {
        var keyboard = new TimelineKeyboard();
        var commands = new Dictionary<VirtualKey, string> {
            [VirtualKey.Space] = "play", [VirtualKey.Enter] = "select_current",
            [VirtualKey.Tab] = "select_next_playing", [VirtualKey.Up] = "previous",
            [VirtualKey.Down] = "next", [VirtualKey.M] = "mark", [VirtualKey.Delete] = "clear_final",
            [VirtualKey.Back] = "clear_final", [VirtualKey.A] = "loop_a", [VirtualKey.B] = "loop_b",
            [VirtualKey.Escape] = "loop_clear", [VirtualKey.Home] = "start", [VirtualKey.End] = "end"
        };
        foreach (var (key, command) in commands)
        {
            Assert.AreEqual(new TimelineKeyAction(command), keyboard.Translate(new(key)));
            Assert.AreEqual(new TimelineKeyAction("consume"), keyboard.Translate(new(key, Repeat: true)));
        }
        Assert.AreEqual(new TimelineKeyAction("select_previous_playing"), keyboard.Translate(new(VirtualKey.Tab, Shift: true)));
        Assert.AreEqual(new TimelineKeyAction("rate", 1), keyboard.Translate(new((VirtualKey)187)));
        Assert.AreEqual(new TimelineKeyAction("rate", -1), keyboard.Translate(new((VirtualKey)189)));
        Assert.AreEqual(new TimelineKeyAction("zoom", 1), keyboard.Translate(new(VirtualKey.Add, Control: true)));
        Assert.AreEqual(new TimelineKeyAction("zoom", -1), keyboard.Translate(new(VirtualKey.Subtract, Control: true)));
    }

    [TestMethod]
    public void ChordsReleaseIndependentlyAndResetWhenFocusLeaves()
    {
        var keyboard = new TimelineKeyboard();
        keyboard.Translate(new(VirtualKey.Number1));
        keyboard.Translate(new(VirtualKey.Number3));
        keyboard.Translate(new(VirtualKey.Number1, Control: true, Released: true));
        Assert.AreEqual(new TimelineKeyAction("nudge", 50), keyboard.Translate(new(VirtualKey.Right, Repeat: true)));
        keyboard.Reset();
        Assert.AreEqual(new TimelineKeyAction("seek", -1), keyboard.Translate(new(VirtualKey.Left)));
        keyboard.Translate(new(VirtualKey.Number2));
        Assert.AreEqual(new TimelineKeyAction("nudge", -10), keyboard.Translate(new(VirtualKey.Left)));
        keyboard.Translate(new(VirtualKey.Number2, Released: true));
        Assert.AreEqual(new TimelineKeyAction("seek", 1), keyboard.Translate(new(VirtualKey.Right)));
    }
}
