using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CueWeave.WinUI.Services;

public sealed class CoreProcess
{
    private readonly object sync = new();
    private Process? active;

    public async Task<JsonElement> CallAsync(string command, JsonObject? payload = null,
        CancellationToken cancellationToken = default)
    {
        var requestId = Guid.NewGuid().ToString("N");
        var request = Encoding.UTF8.GetBytes(new JsonObject {
            ["protocol_version"] = 1,
            ["request_id"] = requestId,
            ["command"] = command,
            ["payload"] = payload ?? new JsonObject()
        }.ToJsonString());
        var executable = FindExecutable();
        using var process = new Process {
            StartInfo = new ProcessStartInfo {
                FileName = executable,
                WorkingDirectory = Path.GetDirectoryName(executable) ?? AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardInputEncoding = Encoding.UTF8,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            }
        };
        process.StartInfo.ArgumentList.Add("rpc");
        process.StartInfo.Environment.Remove("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY");
        process.StartInfo.Environment.Remove("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY_PID");
        process.StartInfo.Environment.Remove("RUST_LOG");
        if (!process.Start()) throw new CoreException("launch_failed", L10n.T("error.coreLaunch"));
        lock (sync) active = process;
        using var registration = cancellationToken.Register(() => {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
        });
        try {
            var stdoutTask = ReadAllAsync(process.StandardOutput.BaseStream, cancellationToken);
            var stderrTask = ReadAllAsync(process.StandardError.BaseStream, cancellationToken);
            await process.StandardInput.BaseStream.WriteAsync(request, cancellationToken);
            process.StandardInput.Close();
            await process.WaitForExitAsync(cancellationToken);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            cancellationToken.ThrowIfCancellationRequested();
            if (process.ExitCode != 0)
            {
                var message = Encoding.UTF8.GetString(stderr).Trim();
                throw new CoreException("process_failed", string.IsNullOrWhiteSpace(message) ? L10n.T("error.coreFailed") : message);
            }
            try
            {
                return CoreRpc.ReadResult(stdout, requestId);
            }
            catch (CoreException exception) when (exception.Code == "invalid_response")
            {
                LogBoot($"rpc {command} stdout={stdout.Length} {CoreRpc.Preview(stdout)}");
                throw;
            }
        } finally {
            lock (sync) if (ReferenceEquals(active, process)) active = null;
        }
    }

    public void Cancel()
    {
        lock (sync) {
            try { if (active is { HasExited: false }) active.Kill(entireProcessTree: true); } catch { }
        }
    }

    internal static string FindExecutable()
    {
        var configured = Environment.GetEnvironmentVariable("CUEWEAVE_CLI");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return configured;
        var bundled = Path.Combine(AppContext.BaseDirectory, "cueweave-cli.exe");
        if (File.Exists(bundled)) return bundled;
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; depth < 10 && directory is not null; depth++, directory = directory.Parent) {
            var candidate = Path.Combine(directory.FullName, "target", "release", "cueweave-cli.exe");
            if (File.Exists(candidate)) return candidate;
        }
        throw new CoreException("cli_missing", L10n.T("error.cliMissingWin"));
    }

    private static async Task<byte[]> ReadAllAsync(Stream stream, CancellationToken token)
    {
        using var buffer = new MemoryStream();
        await stream.CopyToAsync(buffer, token);
        return buffer.ToArray();
    }

    private static void LogBoot(string message)
    {
        try
        {
            File.AppendAllText(
                Path.Combine(AppContext.BaseDirectory, "boot.log"),
                $"{DateTime.Now:O} {message}{Environment.NewLine}");
        }
        catch { /* boot diagnostics must not throw */ }
    }
}
