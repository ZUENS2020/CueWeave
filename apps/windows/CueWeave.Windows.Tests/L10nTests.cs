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
}
