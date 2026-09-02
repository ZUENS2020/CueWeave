using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class WinPathsTests
{
    [TestMethod]
    public void SuggestedFileNameStripsInvalidCharactersAndTruncates()
    {
        Assert.AreEqual("project", WinPaths.SuggestedFileName("   "));
        Assert.AreEqual("晴天foo", WinPaths.SuggestedFileName("晴天/foo"));
        var longName = new string('歌', 80);
        Assert.AreEqual(WinPaths.SuggestedNameLimit, WinPaths.SuggestedFileName(longName).Length);
    }

    [TestMethod]
    public void DetectsTheWindowsPathTooLongMessage()
    {
        Assert.IsTrue(WinPaths.IsTooLong("指定的路径过长。"));
        Assert.IsTrue(WinPaths.IsTooLong(new PathTooLongException("The specified path is too long.")));
        Assert.IsFalse(WinPaths.IsTooLong("file not found"));
    }
}
