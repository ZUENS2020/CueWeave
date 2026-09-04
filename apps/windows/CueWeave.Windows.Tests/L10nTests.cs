using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class L10nTests
{
    [TestMethod]
    public void CatalogsShareTheSameKeys()
    {
        CollectionAssert.AreEquivalent(L10n.EnglishKeys.ToList(), L10n.ChineseKeys.ToList());
        Assert.IsTrue(L10n.EnglishKeys.Count > 0);
        Assert.IsTrue(L10n.EnglishKeys.Contains("action.save"));
    }

    [TestMethod]
    public void PreferenceSwitchesResolvedLanguage()
    {
        L10n.Apply("zh");
        Assert.AreEqual("zh", L10n.Language);
        Assert.AreEqual("保存", L10n.T("action.save"));
        L10n.Apply("en");
        Assert.AreEqual("Save", L10n.T("action.save"));
        L10n.Apply("system");
    }

    [TestMethod]
    public void WindowsShortcutHelpUsesWindowsModifiersInBothLanguages()
    {
        try
        {
            foreach (var language in new[] { "en", "zh" })
            {
                L10n.Apply(language);
                foreach (var key in new[] { "hotkey.zoom.win", "hotkey.undo.win", "hotkey.redo.win", "align.restoreHelp.win" })
                {
                    StringAssert.Contains(L10n.T(key), "Ctrl+");
                    Assert.IsFalse(L10n.T(key).Contains("⌘"));
                }
                Assert.AreNotEqual("hotkeys.help", L10n.T("hotkeys.help"));
            }
        }
        finally { L10n.Apply("system"); }
    }

    [TestMethod]
    public void WrapErrorMapsRawJsonParseFailures()
    {
        L10n.Apply("zh");
        StringAssert.Contains(
            L10n.WrapError("'i' is invalid after a value. Expected either ',', '}', or ']'."),
            "无效响应");
        StringAssert.Contains(L10n.WrapError("指定的路径过长。"), "更短的目录");
        L10n.Apply("system");
    }
}
