using Microsoft.UI.Xaml;
using Microsoft.UI.Windowing;

namespace CueWeave.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "CueWeaveSuzuka.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest).WorkArea;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(Math.Min(1440, area.Width), Math.Min(900, area.Height)));
        RootFrame.Loaded += (_, _) =>
        {
            UpdateWindowConstraints();
            RootFrame.XamlRoot.Changed += (_, _) => UpdateWindowConstraints();
        };
    }

    private void UpdateWindowConstraints()
    {
        if (AppWindow.Presenter is not OverlappedPresenter presenter) return;
        var scale = RootFrame.XamlRoot.RasterizationScale;
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest).WorkArea;
        // XAML uses DIPs; AppWindow uses physical pixels. Keep the entire window on screen.
        var width = Math.Min(area.Width, (int)Math.Ceiling(980 * scale) + AppWindow.Size.Width - AppWindow.ClientSize.Width);
        var height = Math.Min(area.Height, (int)Math.Ceiling(680 * scale) + AppWindow.Size.Height - AppWindow.ClientSize.Height);
        if (presenter.PreferredMinimumWidth != width) presenter.PreferredMinimumWidth = width;
        if (presenter.PreferredMinimumHeight != height) presenter.PreferredMinimumHeight = height;
        var fitted = new Windows.Graphics.SizeInt32(Math.Clamp(AppWindow.Size.Width, width, area.Width), Math.Clamp(AppWindow.Size.Height, height, area.Height));
        if (presenter.State == OverlappedPresenterState.Restored && (fitted.Width != AppWindow.Size.Width || fitted.Height != AppWindow.Size.Height))
            AppWindow.Resize(fitted);
    }

    public void LoadPage() => RootFrame.Navigate(typeof(MainPage));
}
