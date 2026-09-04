using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace CueWeave.WinUI.Controls;

// Measure at the actual viewport width; overflowing commands move to the next row.
public sealed class WrapPanel : Panel
{
    public static readonly DependencyProperty SpacingProperty = DependencyProperty.Register(
        nameof(Spacing), typeof(double), typeof(WrapPanel), new PropertyMetadata(8d,
            (owner, _) => ((WrapPanel)owner).InvalidateMeasure()));
    public double Spacing { get => (double)GetValue(SpacingProperty); set => SetValue(SpacingProperty, value); }

    protected override Size MeasureOverride(Size availableSize)
    {
        var children = Children.Where(child => child.Visibility != Visibility.Collapsed).ToArray();
        foreach (var child in children) child.Measure(new Size(availableSize.Width, double.PositiveInfinity));
        return WrapLayout.Calculate(children.Select(child => child.DesiredSize).ToArray(), availableSize.Width, Spacing).Size;
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        var children = Children.Where(child => child.Visibility != Visibility.Collapsed).ToArray();
        var layout = WrapLayout.Calculate(children.Select(child => child.DesiredSize).ToArray(), finalSize.Width, Spacing);
        for (var index = 0; index < children.Length; index++) children[index].Arrange(layout.Frames[index]);
        return finalSize;
    }
}
