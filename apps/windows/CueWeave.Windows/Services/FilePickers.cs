using Windows.Storage;
using Windows.Storage.Pickers;

namespace CueWeave.WinUI.Services;

internal static class FilePickers
{
    public static async Task<StorageFile?> OpenAsync(string title, params string[] extensions)
    {
        foreach (var location in new[] { PickerLocationId.MusicLibrary, PickerLocationId.ComputerFolder })
        {
            try
            {
                var picker = new FileOpenPicker
                {
                    SuggestedStartLocation = location,
                    ViewMode = PickerViewMode.List,
                    CommitButtonText = title
                };
                foreach (var extension in extensions) picker.FileTypeFilter.Add(extension);
                Bind(picker);
                var file = await picker.PickSingleFileAsync();
                if (file is not null) BootLog.Append($"picked open {file.Path.Length} {file.Path}");
                return file;
            }
            catch (Exception exception) when (WinPaths.IsTooLong(exception) && location != PickerLocationId.ComputerFolder)
            {
                BootLog.Append($"picker open {location} {exception.Message}");
            }
        }
        return null;
    }

    public static async Task<StorageFile?> SaveAsync(string title, string extension, string name)
    {
        var suggested = WinPaths.SuggestedFileName(name);
        foreach (var location in new[] { PickerLocationId.Desktop, PickerLocationId.ComputerFolder })
        {
            try
            {
                var picker = new FileSavePicker
                {
                    SuggestedStartLocation = location,
                    SuggestedFileName = suggested,
                    CommitButtonText = title
                };
                picker.FileTypeChoices.Add("CueWeave", [extension]);
                Bind(picker);
                var file = await picker.PickSaveFileAsync();
                if (file is not null) BootLog.Append($"picked save {file.Path.Length} {file.Path}");
                return file;
            }
            catch (Exception exception) when (WinPaths.IsTooLong(exception) && location != PickerLocationId.ComputerFolder)
            {
                BootLog.Append($"picker save {location} {suggested} {exception.Message}");
            }
        }
        return null;
    }

    private static void Bind(object picker) =>
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(CueWeave.WinUI.App.MainWindow));
}
