using CueWeave.WinUI.Timeline;
using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class TimelineViewportTests
{
    [TestMethod]
    public void ZoomNotificationIncludesTheInitialNaNSentinel()
    {
        Assert.IsTrue(TimelineViewport.ShouldNotifyZoom(double.NaN, 2));
        Assert.IsFalse(TimelineViewport.ShouldNotifyZoom(2, 2));
        Assert.IsFalse(TimelineViewport.ShouldNotifyZoom(2, 2.001));
        Assert.IsTrue(TimelineViewport.ShouldNotifyZoom(2, 6.7));
    }

    [TestMethod]
    public void FullDocumentClicksMapToExactTargetTimes()
    {
        var viewport = NewViewport();
        Assert.AreEqual(14_909.1, viewport.TimeAt(100, 1_000), .001);
        Assert.AreEqual(74_545.5, viewport.TimeAt(500, 1_000), .001);
        Assert.AreEqual(134_181.9, viewport.TimeAt(900, 1_000), .001);
    }

    [TestMethod]
    public void DefaultAlignmentZoomIsTwo()
    {
        var viewport = NewViewport();
        viewport.SetZoom(2, 74_545.5);
        Assert.AreEqual(2, viewport.Zoom, .0001);
        Assert.AreEqual(74_545.5, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
    }

    [TestMethod]
    public void SliderAndKeyboardZoomCenterOnPlayhead()
    {
        var viewport = NewViewport();
        viewport.SetZoom(2, 74_545.5);
        Assert.AreEqual(2, viewport.Zoom, .0001);
        Assert.AreEqual(74_545.5, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
        viewport.SetZoom(12, 74_545.5);
        Assert.AreEqual(12, viewport.Zoom, .0001);
        Assert.AreEqual(74_545.5, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
        viewport.SetZoom(100, 74_545.5);
        Assert.AreEqual(100, viewport.Zoom, .0001);
    }

    [TestMethod]
    public void GestureZoomKeepsGestureAnchorAtSamePixel()
    {
        var viewport = NewViewport();
        viewport.SetZoom(4, 70_000);
        var anchor = viewport.TimeAt(730, 1_000);
        viewport.ZoomAt(1.8, anchor);
        Assert.AreEqual(730, viewport.XAt(anchor, 1_000), .001);
    }

    [TestMethod]
    public void SelectionUsesStrictFourDipThresholdAndAddsMargin()
    {
        Assert.IsFalse(TimelineViewport.IsSelection(10, 14));
        Assert.IsTrue(TimelineViewport.IsSelection(10, 14.01));
        var viewport = NewViewport();
        viewport.ZoomSelection(250, 750, 1_000);
        Assert.AreEqual(74_545.5, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
        Assert.AreEqual(149_091 * .54, viewport.VisibleDurationMs, .001);
    }

    [TestMethod]
    public void FollowCentersOnlyOutsideGestures()
    {
        var viewport = NewViewport(); viewport.SetZoom(10, 50_000); viewport.FollowEnabled = true;
        var before = viewport.VisibleStartMs; viewport.GestureActive = true; viewport.Follow(100_000);
        Assert.AreEqual(before, viewport.VisibleStartMs);
        viewport.GestureActive = false; viewport.Follow(100_000);
        Assert.AreEqual(100_000, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
    }

    [TestMethod]
    public void UserZoomHoldsFollowUntilTheHoldExpires()
    {
        var viewport = NewViewport(); viewport.SetZoom(8, 50_000); viewport.FollowEnabled = true;
        var before = viewport.VisibleStartMs;
        viewport.NoteUserInteraction(1);
        viewport.Follow(120_000);
        Assert.AreEqual(before, viewport.VisibleStartMs);
        viewport.Follow(120_000);
        Assert.AreEqual(120_000, viewport.VisibleStartMs + viewport.VisibleDurationMs / 2, .001);
    }

    [TestMethod]
    public void LoopWrapsToAOnlyAfterCrossingBWhilePlaying()
    {
        Assert.AreEqual(12_000, TimelineViewport.ApplyLoop(12_000, false, 1_000, 8_000), .001);
        Assert.AreEqual(7_999, TimelineViewport.ApplyLoop(7_999, true, 1_000, 8_000), .001);
        Assert.AreEqual(1_000, TimelineViewport.ApplyLoop(8_000, true, 1_000, 8_000), .001);
        Assert.AreEqual(8_000, TimelineViewport.ApplyLoop(8_000, true, null, 8_000), .001);
    }

    [TestMethod]
    public void NudgeDirectionsAndTrackLayoutMatchContract()
    {
        Assert.AreEqual(-1, TimelineViewport.NudgeDelta(1, false));
        Assert.AreEqual(1, TimelineViewport.NudgeDelta(1, true));
        Assert.AreEqual(-10, TimelineViewport.NudgeDelta(10, false));
        Assert.AreEqual(10, TimelineViewport.NudgeDelta(10, true));
        Assert.AreEqual(-50, TimelineViewport.NudgeDelta(50, false));
        Assert.AreEqual(50, TimelineViewport.NudgeDelta(50, true));
        var layout = TimelineViewport.Layout(700);
        Assert.AreEqual(24, layout.Ruler); Assert.AreEqual(72, layout.Lyrics);
        Assert.AreEqual(layout.Waveform, layout.Bands); Assert.AreEqual(302, layout.Waveform);
    }

    [TestMethod]
    public void PlainArrowStepTracksOnePercentOfVisibleDuration()
    {
        var viewport = NewViewport(); Assert.AreEqual(1_490.91, viewport.SeekStep, .001);
        viewport.SetZoom(100, 74_545.5);         Assert.AreEqual(14.9091, viewport.SeekStep, .001);
    }

    [TestMethod]
    public void AnalyzeReadsAGeneratedWavFromAFileStream()
    {
        var path = Path.Combine(Path.GetTempPath(), $"cueweave-{Guid.NewGuid():N}.wav");
        WriteSineWav(path);
        try
        {
            var data = WaveformAnalyzer.Analyze(path, 64, CancellationToken.None);
            Assert.AreEqual(64, data.Peak.Length);
            Assert.IsTrue(data.Peak.Max() > .2f);
            Assert.IsTrue(data.Low.Max() > 0 || data.Mid.Max() > 0 || data.High.Max() > 0);
        }
        finally { File.Delete(path); }
    }

    [TestMethod]
    public void PlaybackRateStepsAlongSupportedPresets()
    {
        Assert.AreEqual(1.25, TimelineViewport.SteppedRate(1.0, 1), .0001);
        Assert.AreEqual(0.75, TimelineViewport.SteppedRate(1.0, -1), .0001);
        Assert.AreEqual(2.0, TimelineViewport.SteppedRate(2.0, 1), .0001);
        Assert.AreEqual(0.5, TimelineViewport.SteppedRate(0.5, -1), .0001);
    }

    [TestMethod]
    public void NextFollowsTheLyricAfterThePlayhead()
    {
        ulong[] ids = [1, 2, 3];
        Assert.AreEqual(2UL, TimelineViewport.FollowingSegmentId(1, ids));
        Assert.AreEqual(3UL, TimelineViewport.FollowingSegmentId(3, ids));
        Assert.AreEqual(1UL, TimelineViewport.FollowingSegmentId(null, ids));
        Assert.IsTrue(TimelineViewport.KeepsFollowSelection(1));
        Assert.IsFalse(TimelineViewport.KeepsFollowSelection(-1));
    }

    [TestMethod]
    public void BeyondFixtureProducesDistinctWaveformAndBandTracks()
    {
        var path = Environment.GetEnvironmentVariable("CUEWEAVE_AUDIO_FIXTURE");
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) Assert.Inconclusive("CUEWEAVE_AUDIO_FIXTURE is not available.");
        var data = WaveformAnalyzer.Analyze(path!, 512, CancellationToken.None);
        Assert.AreEqual(512, data.Peak.Length); Assert.IsTrue(data.Peak.Max() > .2f);
        Assert.IsTrue(data.Low.Max() > 0); Assert.IsTrue(data.Mid.Max() > 0); Assert.IsTrue(data.High.Max() > 0);
        Assert.IsFalse(data.Low.SequenceEqual(data.Mid)); Assert.IsFalse(data.Mid.SequenceEqual(data.High));
    }

    private static TimelineViewport NewViewport()
    {
        var viewport = new TimelineViewport(); viewport.SetDocument(149_091); return viewport;
    }

    private static void WriteSineWav(string path)
    {
        const int sampleRate = 8000;
        const int samples = 4000;
        using var writer = new BinaryWriter(File.Create(path));
        writer.Write("RIFF"u8);
        writer.Write(36 + samples * 2);
        writer.Write("WAVEfmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(sampleRate);
        writer.Write(sampleRate * 2);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(samples * 2);
        for (var i = 0; i < samples; i++)
            writer.Write((short)(Math.Sin(2 * Math.PI * 440 * i / sampleRate) * 20_000));
    }
}
