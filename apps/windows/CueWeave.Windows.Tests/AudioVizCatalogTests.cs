using CueWeave.WinUI.Timeline;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class AudioVizCatalogTests
{
    [TestMethod]
    public void BuiltinAdaptersMatchTheCoreContract()
    {
        Assert.AreEqual(7, AudioVizCatalog.All.Length);
        CollectionAssert.AreEqual(
            new[] { "peak", "rms", "peakRms", "bands", "specLinear", "specLog", "specMel" },
            AudioVizCatalog.All.Select(adapter => adapter.Id).ToArray());
        Assert.AreEqual("waveform", AudioVizCatalog.Find("peakRms")!.Surface);
        CollectionAssert.AreEqual(new[] { "peak", "rms" }, AudioVizCatalog.Find("peakRms")!.Series);
        Assert.AreEqual("bands", AudioVizCatalog.Find("bands")!.Surface);
        Assert.AreEqual("mel", AudioVizCatalog.Find("specMel")!.Scale);
        Assert.IsNull(AudioVizCatalog.Find("onset"));
    }
}
