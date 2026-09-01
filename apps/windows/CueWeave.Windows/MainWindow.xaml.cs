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
        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1440, 900));
        RootFrame.Navigate(typeof(MainPage));
    }
}
