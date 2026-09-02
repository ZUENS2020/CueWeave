using Microsoft.UI.Xaml;

namespace CueWeave.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1440, 900));
    }

    public void LoadPage() => RootFrame.Navigate(typeof(MainPage));
}
