using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class PlaybackTickTests
{
    [TestMethod]
    public void AdvancingClockIsSampledOnceAndNeverSeeksDuringOrdinaryPlayback()
    {
        var reads = 0;
        var seeks = new List<double>();
        var position = PlaybackTick.Update(() => 1_000 + ++reads, seeks.Add, true, null, null);
        Assert.AreEqual(1, reads);
        Assert.AreEqual(1_001d, position);
        Assert.AreEqual(0, seeks.Count);
    }

    [TestMethod]
    public void LoopCrossingSeeksExactlyOnceAndPausedPlaybackDoesNotSeek()
    {
        var seeks = new List<double>();
        Assert.AreEqual(100d, PlaybackTick.Update(() => 500, seeks.Add, true, 100, 500));
        CollectionAssert.AreEqual(new[] {100d}, seeks);
        Assert.AreEqual(500d, PlaybackTick.Update(() => 500, seeks.Add, false, 100, 500));
        Assert.AreEqual(1, seeks.Count);
    }
}
