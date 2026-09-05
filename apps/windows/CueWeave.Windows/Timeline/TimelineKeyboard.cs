using Windows.System;

namespace CueWeave.WinUI.Timeline;

public enum ShortcutOwner { Workspace, Editor, NativeControl, Modal }
public readonly record struct TimelineKey(VirtualKey Key, bool Control = false, bool Shift = false,
    bool Alt = false, bool Repeat = false, bool Released = false);
public readonly record struct TimelineKeyAction(string Command, int Direction = 0);

// Pure keyboard policy: independent of WinUI focus and routed events, shared by tests.
public sealed class TimelineKeyboard
{
    private readonly List<VirtualKey> heldSteps = [];
    public void Reset() => heldSteps.Clear();

    public static bool IsReserved(VirtualKey key, ShortcutOwner owner) => owner switch
    {
        ShortcutOwner.Editor or ShortcutOwner.Modal => true,
        // A closed picker/slider still owns native navigation, but not N/M/A/B.
        ShortcutOwner.NativeControl => key is VirtualKey.Left or VirtualKey.Right or VirtualKey.Up
            or VirtualKey.Down or VirtualKey.Home or VirtualKey.End or VirtualKey.PageUp
            or VirtualKey.PageDown or VirtualKey.Tab or VirtualKey.Enter or VirtualKey.Space,
        _ => false
    };

    public TimelineKeyAction? Translate(TimelineKey input)
    {
        var key = input.Key;
        var step = key switch { VirtualKey.Number1 => 1, VirtualKey.Number2 => 10, VirtualKey.Number3 => 50, _ => 0 };
        // Key releases always clear held state, even if modifiers changed while held.
        if (input.Released) { heldSteps.Remove(key); return null; }
        var plus = key == VirtualKey.Add || (int)key == 187;
        var minus = key == VirtualKey.Subtract || (int)key == 189;
        if (input.Alt) return null;
        if (input.Control) return plus || minus ? new("zoom", plus ? 1 : -1) : null;
        if (plus || minus) return new("rate", plus ? 1 : -1);
        if (input.Shift && key != VirtualKey.Tab) return null;
        if (step != 0)
        {
            if (!heldSteps.Contains(key)) heldSteps.Add(key);
            return new("consume");
        }
        if (key is VirtualKey.Left or VirtualKey.Right)
        {
            var direction = key == VirtualKey.Right ? 1 : -1;
            var held = heldSteps.LastOrDefault() switch { VirtualKey.Number1 => 1, VirtualKey.Number2 => 10, VirtualKey.Number3 => 50, _ => 0 };
            return held == 0 ? new("seek", direction) : new("nudge", direction * held);
        }
        TimelineKeyAction? action = key switch
        {
            VirtualKey.Tab => new TimelineKeyAction(input.Shift ? "select_previous_playing" : "select_next_playing"),
            VirtualKey.Home => new("start"), VirtualKey.End => new("end"),
            VirtualKey.Enter => new("select_current"), VirtualKey.Space => new("play"),
            VirtualKey.A => new("loop_a"), VirtualKey.B => new("loop_b"), VirtualKey.Escape => new("loop_clear"),
            VirtualKey.Down => new("next"), VirtualKey.Up => new("previous"),
            VirtualKey.C => new("toggle_follow_current"),
            VirtualKey.M => new("mark"), VirtualKey.N => new("toggle_follow_next"),
            VirtualKey.Delete or VirtualKey.Back => new("clear_final"),
            (VirtualKey)188 => new("nudge", -1), (VirtualKey)190 => new("nudge", 1),
            _ => (TimelineKeyAction?)null
        };
        // Consume repeats so controls underneath cannot activate, without toggling twice.
        return input.Repeat && action is not null ? new("consume") : action;
    }
}
