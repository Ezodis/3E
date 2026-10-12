using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Diagnostics;

namespace ThreeFingerDragOnWindows;

public static class SsmsTheme {
    public const string ThemeProperty = "environment.visualExperience.colorTheme";
    private const string LightId = "{de3dbbcd-f642-433c-8353-8f1df4370aba}";
    private const string DarkId = "{1ded0138-47ce-435e-84ef-9ec1f439b749}";
    public sealed record Theme(string Id, string Name, bool Light);
    public static string[] CurrentThemeNames { get; private set; } = Array.Empty<string>();
    private static readonly JsonDocumentOptions Options = new() { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true };

    // SSMS 22 uses the Visual Studio JSON settings store. Change just this value;
    // keep comments, connection settings and other options intact.
    public static string FollowSystem(string text) => SetTheme(text, "system");

    public static string SetTheme(string text, string theme) {
        var parsed = JsonNode.Parse(text, documentOptions: Options)?.AsObject() ?? throw new InvalidDataException("Invalid SSMS settings.");
        if (parsed[ThemeProperty]?.GetValue<string>() == theme) return text;
        string encoded = JsonSerializer.Serialize(theme);
        var bytes = Encoding.UTF8.GetBytes(text);
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
        while (reader.Read()) {
            if (reader.CurrentDepth != 1 || reader.TokenType != JsonTokenType.PropertyName || !reader.ValueTextEquals(ThemeProperty)) continue;
            reader.Read();
            int start = checked((int)reader.TokenStartIndex), end = checked((int)reader.BytesConsumed);
            return Encoding.UTF8.GetString(bytes, 0, start) + encoded + Encoding.UTF8.GetString(bytes, end, bytes.Length - end);
        }
        int closing = text.LastIndexOf('}');
        string before = text[..closing].TrimEnd();
        string comma = parsed.Count > 0 && !before.EndsWith(',') ? "," : "";
        string updated = text.Insert(closing, comma + "\n  \"" + ThemeProperty + "\": " + encoded + "\n");
        if (JsonNode.Parse(updated, documentOptions: Options)?[ThemeProperty]?.GetValue<string>() != theme) throw new InvalidDataException("Could not update SSMS theme safely.");
        return updated;
    }

    public static IReadOnlyList<Theme> InstalledThemes() {
        var idePaths = new List<string>();
        foreach (var process in Process.GetProcessesByName("SSMS")) {
            using (process) { try { idePaths.Add(Path.GetDirectoryName(process.MainModule.FileName)); } catch { } }
        }
        foreach (string programFiles in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) }.Distinct()) {
            if (!Directory.Exists(programFiles)) continue;
            foreach (string folder in Directory.EnumerateDirectories(programFiles, "Microsoft SQL Server Management Studio 22*"))
                foreach (string channel in new[] { "Release", "Preview" }) idePaths.Add(Path.Combine(folder, channel, "Common7", "IDE"));
        }
        foreach (string ide in idePaths.Distinct()) {
            string definitions = Path.Combine(ide, "CommonExtensions", "Platform", "Themes.Registration.pkgdef");
            if (!File.Exists(definitions)) continue;
            var themes = new List<Theme> { new(LightId, "Light", true), new(DarkId, "Dark", false) };
            foreach (Match block in Regex.Matches(File.ReadAllText(definitions), @"(?ms)^\[\$RootKey\$\\Themes\\(?<id>\{[0-9a-fA-F-]{36}\})\]\s*(?<body>.*?)(?=^\[|\z)")) {
                string body = block.Groups["body"].Value;
                string name = Regex.Match(body, "(?m)^@=\"([^\"]+)\"").Groups[1].Value;
                string fallback = Regex.Match(body, "\"FallbackId\"=\"([^\"]+)\"").Groups[1].Value;
                bool light = fallback.Equals(LightId, StringComparison.OrdinalIgnoreCase);
                if (name.Length > 0 && (light || fallback.Equals(DarkId, StringComparison.OrdinalIgnoreCase)))
                    themes.Add(new Theme(block.Groups["id"].Value, name, light));
            }
            return themes.DistinctBy(theme => theme.Id).ToArray();
        }
        return Array.Empty<Theme>();
    }

    public static Theme Choose(IReadOnlyList<Theme> themes, bool light, string current) {
        string previous = current is "system" or null ? (light ? LightId : DarkId) : current == "light" ? LightId : current == "dark" ? DarkId : current;
        var choices = themes.Where(theme => theme.Light == light && !theme.Id.Equals(previous, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (choices.Length == 0) choices = themes.Where(theme => theme.Light == light).ToArray();
        return choices.Length == 0 ? null : choices[Random.Shared.Next(choices.Length)];
    }

    public static string RotationPeriod(DateTime now, bool light) {
        DateTime date = now.Hour < 12 ? now.Date.AddDays(-1) : now.Date;
        return date.ToString("yyyy-MM-dd") + (now.Hour >= 12 && now.Hour < 20 ? "/day/" : "/night/") + light;
    }

    public static int Configure(Action<Exception> log, bool light, bool rotate) {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "SSMS");
        if (!Directory.Exists(root)) return 0;
        var themes = InstalledThemes();
        if (themes.Count == 0) return 0;
        int configured = 0;
        var activeNames = new List<string>();
        foreach (string profile in Directory.EnumerateDirectories(root, "22.*")) {
            string path = Path.Combine(profile, "settings.json");
            if (!File.Exists(path)) continue;
            try {
                string original = File.ReadAllText(path);
                var json = JsonNode.Parse(original, documentOptions: Options);
                string current = json?[ThemeProperty]?.GetValue<string>();
                Theme selected = themes.FirstOrDefault(theme => theme.Light == light && theme.Id.Equals(current, StringComparison.OrdinalIgnoreCase));
                if (rotate || selected == null) selected = Choose(themes, light, current);
                if (selected == null) continue;
                string updated = SetTheme(original, selected.Id);
                if (updated != original) {
                    if (!File.Exists(path + ".3EWindows-theme.bak")) File.Copy(path, path + ".3EWindows-theme.bak");
                    File.WriteAllText(path + ".3e.tmp", updated, new UTF8Encoding(false));
                    File.Move(path + ".3e.tmp", path, true);
                }
                configured++;
                activeNames.Add(selected.Name);
            } catch (Exception ex) { log(ex); }
        }
        CurrentThemeNames = activeNames.ToArray();
        return configured;
    }
}
