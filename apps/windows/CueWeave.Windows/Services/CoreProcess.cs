using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CueWeave.WinUI.Services;

public sealed class CoreException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public sealed class CoreProcess
{
    private readonly object sync = new();
    private Process? active;

    public async Task<JsonElement> CallAsync(string command, JsonObject? payload = null,
        CancellationToken cancellationToken = default)
    {
        var requestId = Guid.NewGuid().ToString("N");
        var request = new JsonObject {
            ["protocol_version"] = 1,
            ["request_id"] = requestId,
            ["command"] = command,
            ["payload"] = payload ?? new JsonObject()
        };
        using var process = new Process {
            StartInfo = new ProcessStartInfo {
                FileName = FindExecutable(),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };
        process.StartInfo.ArgumentList.Add("rpc");
        if (!process.Start()) throw new CoreException("launch_failed", L10n.T("error.coreLaunch"));
        lock (sync) active = process;
        using var registration = cancellationToken.Register(() => {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
        });
        try {
            await process.StandardInput.WriteAsync(request.ToJsonString());
            process.StandardInput.Close();
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);
            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            cancellationToken.ThrowIfCancellationRequested();
            if (process.ExitCode != 0)
                throw new CoreException("process_failed", string.IsNullOrWhiteSpace(stderr) ? L10n.T("error.coreFailed") : stderr.Trim());
            using var document = JsonDocument.Parse(stdout);
            var root = document.RootElement;
            if (root.GetProperty("request_id").GetString() != requestId)
                throw new CoreException("invalid_response", L10n.T("error.coreMismatch"));
            if (!root.GetProperty("ok").GetBoolean()) {
                var error = root.GetProperty("error");
                throw new CoreException(error.GetProperty("code").GetString() ?? "core_error",
                    error.GetProperty("message").GetString() ?? L10n.T("error.coreFailed"));
            }
            return root.TryGetProperty("result", out var result) ? result.Clone() : default;
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
}
