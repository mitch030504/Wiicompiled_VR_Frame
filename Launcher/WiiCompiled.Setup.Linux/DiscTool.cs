using System.Security.Cryptography;
using WiiCompiled.Setup.Common;

namespace WiiCompiled.Setup.Linux;

/// <summary>
/// Validates and extracts the user's own Mario Kart Wii disc via `nodtool` (see
/// WiiCompiled.Setup.Common/NodToolProvider.cs) - a prebuilt, MIT/Apache-2.0-licensed CLI from
/// encounter/nod, replacing the earlier dependency on a system-installed `dolphin-tool`
/// (GPL-2.0-or-later, and not reliably packaged standalone by every distro).
/// </summary>
internal static class DiscTool
{
    public static async Task ValidateAndExtractAsync(
        string isoPath, ProjectManifest manifest, string assetsDirectory, string workspace,
        string? nodToolBin, IInstallReporter reporter, CancellationToken cancellationToken)
    {
        var nodTool = nodToolBin ?? await NodToolProvider.ResolveAsync(workspace, cancellationToken);

        // `nodtool info` only decodes the disc/partition headers (milliseconds); `nodtool extract`
        // copies the whole data partition to disk (tens of seconds for a custom-track-heavy MKWii
        // ISO). Checking the game ID first, before extracting, means a wrong disc fails fast -
        // matching the original dolphin-tool `header` step this replaces.
        reporter.Progress(InstallStages.ExtractDisc, "Reading the disc header", 2);
        var info = NodToolInfoParser.Parse(await RunInfoAsync(nodTool, isoPath, cancellationToken));
        if (!string.Equals(info.GameId, manifest.GameId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"This disc is '{info.GameId}', not the expected '{manifest.GameId}' (Mario Kart Wii, region {manifest.Region}). " +
                "Only your own legally-owned copy of that exact game/region can be used.");
        }

        reporter.Progress(InstallStages.ExtractDisc, "Extracting the disc image", 4);
        Directory.CreateDirectory(assetsDirectory);
        var dataDir = Path.Combine(assetsDirectory, "DATA");
        var backup = dataDir + ".replaced";
        if (!Directory.Exists(dataDir) && Directory.Exists(backup)) Directory.Move(backup, dataDir);
        if (Directory.Exists(backup)) Directory.Delete(backup, recursive: true);
        var staging = dataDir + ".extracting";
        if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        try
        {
            await RunExtractAsync(nodTool, isoPath, staging, cancellationToken);
            var dolPath = Path.Combine(staging, "sys", "main.dol");
            var relPath = Path.Combine(staging, "files", "rel", "StaticR.rel");
            if (!File.Exists(dolPath)) throw new FileNotFoundException("nodtool did not produce main.dol", dolPath);
            if (!File.Exists(relPath)) throw new FileNotFoundException("nodtool did not produce StaticR.rel", relPath);

            var dolSha = Sha256Of(dolPath);
            var relSha = Sha256Of(relPath);
            if (!string.Equals(dolSha, manifest.DolSha256, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"main.dol sha256 mismatch: expected {manifest.DolSha256}, got {dolSha}. " +
                    "This disc revision does not match what this project's manifest is pinned to.");
            }
            if (!string.Equals(relSha, manifest.RelSha256, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"StaticR.rel sha256 mismatch: expected {manifest.RelSha256}, got {relSha}. " +
                    "This disc revision does not match what this project's manifest is pinned to.");
            }

            cancellationToken.ThrowIfCancellationRequested();
            if (Directory.Exists(dataDir)) Directory.Move(dataDir, backup);
            try
            {
                Directory.Move(staging, dataDir);
            }
            catch
            {
                if (Directory.Exists(backup)) Directory.Move(backup, dataDir);
                throw;
            }
            FileSystemUtilities.WriteAtomic(Path.Combine(assetsDirectory, "main.dol"),
                File.ReadAllBytes(Path.Combine(dataDir, "sys", "main.dol")));
            FileSystemUtilities.WriteAtomic(Path.Combine(assetsDirectory, "StaticR.rel"),
                File.ReadAllBytes(Path.Combine(dataDir, "files", "rel", "StaticR.rel")));
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        }
        if (Directory.Exists(backup)) Directory.Delete(backup, recursive: true);
        reporter.Progress(InstallStages.ExtractDisc, "Disc validated and extracted", 6);
    }

    private static async Task<string> RunInfoAsync(string nodTool, string isoPath, CancellationToken cancellationToken)
    {
        var startInfo = new System.Diagnostics.ProcessStartInfo(nodTool)
        {
            ArgumentList = { "info", isoPath },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        using var process = System.Diagnostics.Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start {nodTool}.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        try
        {
            await process.WaitForExitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
            throw;
        }
        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"nodtool could not read this disc image (exit {process.ExitCode}): {stderr}{stdout}".Trim());
        }
        return stdout;
    }

    private static string Sha256Of(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static async Task RunExtractAsync(string nodTool, string isoPath, string outDir, CancellationToken cancellationToken)
    {
        var startInfo = new System.Diagnostics.ProcessStartInfo(nodTool)
        {
            ArgumentList = { "extract", isoPath, outDir, "-q" },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = System.Diagnostics.Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start {nodTool}.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        try
        {
            await process.WaitForExitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
            throw;
        }
        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"nodtool extract {isoPath} failed (exit {process.ExitCode}): {stderr}{stdout}");
        }
    }
}
