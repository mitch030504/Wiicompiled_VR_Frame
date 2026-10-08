using System.Security.Cryptography;
using WiiCompiled.Setup.Linux;
using Xunit;

namespace Translator.Tests;

public sealed class LinuxDiscExtractionTests
{
    private sealed class Reporter : IInstallReporter
    {
        public void Progress(string stage, string message, int percent) { }
        public void Diagnostic(string line) { }
    }

    [Theory]
    [InlineData("valid")]
    [InlineData("wrong-hash")]
    [InlineData("failed")]
    [InlineData("cancelled")]
    [InlineData("recovery")]
    public async Task ExtractionPreservesLiveDataUntilValidationSucceeds(string mode)
    {
        if (!OperatingSystem.IsLinux()) return;
        var root = Path.Combine(Path.GetTempPath(), "linux-disc-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var assets = Path.Combine(root, "Assets");
            var data = Path.Combine(assets, "DATA");
            Directory.CreateDirectory(data);
            File.WriteAllText(Path.Combine(data, "old"), "working install");
            if (mode == "recovery") Directory.Move(data, data + ".replaced");
            var tool = Path.Combine(root, "nodtool");
            File.WriteAllText(tool, """
                #!/bin/bash
                if [[ "$1" == info ]]; then echo 'Game ID: RMCP01'; exit 0; fi
                mkdir -p "$3/sys" "$3/files/rel"
                printf dol > "$3/sys/main.dol"
                printf rel > "$3/files/rel/StaticR.rel"
                """ + "\n" + (mode is "failed" or "recovery" ? "exit 1\n" : mode == "cancelled" ? "sleep 30\n" : "exit 0\n"));
            File.SetUnixFileMode(tool, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            var manifest = new ProjectManifest
            {
                GameId = "RMCP01", Region = "P",
                DolSha256 = mode == "wrong-hash" ? new string('0', 64) : Hash("dol"),
                RelSha256 = Hash("rel")
            };
            using var cancellation = new CancellationTokenSource();
            if (mode == "cancelled") cancellation.CancelAfter(TimeSpan.FromMilliseconds(200));
            var task = DiscTool.ValidateAndExtractAsync("disc.iso", manifest, assets, root, tool, new Reporter(), cancellation.Token);
            if (mode == "valid")
            {
                await task;
                Assert.False(File.Exists(Path.Combine(data, "old")));
                Assert.Equal("dol", File.ReadAllText(Path.Combine(data, "sys", "main.dol")));
                Assert.Equal("rel", File.ReadAllText(Path.Combine(assets, "StaticR.rel")));
            }
            else
            {
                await Assert.ThrowsAnyAsync<Exception>(() => task);
                Assert.Equal("working install", File.ReadAllText(Path.Combine(data, "old")));
            }
            Assert.False(Directory.Exists(data + ".extracting"));
            Assert.False(Directory.Exists(data + ".replaced"));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
}
