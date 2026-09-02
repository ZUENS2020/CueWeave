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
        Assert.IsTrue(WinPaths.IsTooLong("指定的路径无效。指定的路径过长，超出了最大长度。"));
        Assert.IsTrue(WinPaths.IsTooLong(new PathTooLongException("The specified path is too long.")));
        Assert.IsFalse(WinPaths.IsTooLong("file not found"));
    }

    [TestMethod]
    public void UncAndMappedSharesNeedALocalCopy()
    {
        Assert.IsTrue(WinPaths.NeedsLocalCopy(@"\\nas\music\Beyond.mp3"));
        Assert.IsTrue(WinPaths.NeedsLocalCopy("//nas/music/Beyond.mp3"));
    }

    [TestMethod]
    public void MaterializeCopiesNetworkOrLongSourcesIntoTemp()
    {
        var source = Path.Combine(Path.GetTempPath(), "cueweave-winpaths", Guid.NewGuid().ToString("N"), "song.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(source)!);
        File.WriteAllBytes(source, [1, 2, 3, 4]);
        try
        {
            var local = WinPaths.Materialize(source);
            Assert.IsTrue(File.Exists(local));
            CollectionAssert.AreEqual(new byte[] { 1, 2, 3, 4 }, File.ReadAllBytes(local));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(source)!, true);
        }
    }
}
