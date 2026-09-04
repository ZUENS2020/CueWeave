using Windows.Foundation;

namespace CueWeave.WinUI.Controls;

public static class WrapLayout
{
    public static (Size Size, Rect[] Frames) Calculate(IReadOnlyList<Size> sizes, double width, double spacing)
    {
        width = double.IsNaN(width) ? 0 : Math.Max(0, width);
        spacing = double.IsFinite(spacing) ? Math.Max(0, spacing) : 0;
        var frames = new Rect[sizes.Count];
        double x = 0, y = 0, rowHeight = 0, usedWidth = 0;
        for (var index = 0; index < sizes.Count; index++)
        {
            var size = sizes[index];
            var itemWidth = Math.Min(width, Math.Max(0, size.Width));
            if (x > 0 && x + itemWidth > width)
            {
                x = 0; y += rowHeight + spacing; rowHeight = 0;
            }
            frames[index] = new Rect(x, y, itemWidth, size.Height);
            usedWidth = Math.Max(usedWidth, x + itemWidth);
            x += itemWidth + spacing;
            rowHeight = Math.Max(rowHeight, size.Height);
        }
        return (new Size(usedWidth, y + rowHeight), frames);
    }
}
