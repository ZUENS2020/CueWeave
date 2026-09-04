using CueWeave.WinUI.Controls;
using Windows.Foundation;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class WrapLayoutTests
{
    [TestMethod]
    public void CommandsWrapWithoutOverlappingOrEscapingTheViewport()
    {
        // English buttons are substantially wider than Chinese labels.
        foreach (var width in new[] { 320d, 480d, 640d, 900d })
        {
            var layout = WrapLayout.Calculate([new(36, 32), new(104, 32), new(120, 32), new(180, 40), new(88, 32)], width, 8);
            Assert.IsTrue(layout.Size.Width <= width);
            for (var index = 0; index < layout.Frames.Length; index++)
            {
                var frame = layout.Frames[index];
                Assert.IsTrue(frame.Right <= width);
                Assert.IsTrue(frame.Bottom <= layout.Size.Height);
                foreach (var previous in layout.Frames.Take(index))
                    Assert.IsTrue(frame.Left >= previous.Right || frame.Top >= previous.Bottom);
            }
        }
    }

    [TestMethod]
    public void ExactFitStaysOnOneRowAndOversizedItemsAreConstrained()
    {
        var fit = WrapLayout.Calculate([new(100, 32), new(100, 32)], 208, 8);
        Assert.AreEqual(32d, fit.Size.Height);
        var narrow = WrapLayout.Calculate([new(500, 40), new(100, 32)], 200, 8);
        Assert.AreEqual(200d, narrow.Frames[0].Width);
        Assert.AreEqual(48d, narrow.Frames[1].Top);
        Assert.AreEqual(new Size(0, 0), WrapLayout.Calculate([], 200, 8).Size);
    }
}
