using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace CueWeave.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1440, 900));
        RootFrame.Navigate(typeof(MainPage));
    }
}
