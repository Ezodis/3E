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

    public static string SetTheme(string text, string theme) => SetProperty(text, ThemeProperty, theme);

    // Edits one top-level string in a JSON-with-comments settings file in place.
    public static string SetProperty(string text, string property, string theme) {
        var parsed = JsonNode.Parse(text, documentOptions: Options)?.AsObject() ?? throw new InvalidDataException("Invalid settings file.");
        if (parsed[property]?.GetValueKind() == JsonValueKind.String && parsed[property].GetValue<string>() == theme) return text;
        string encoded = JsonSerializer.Serialize(theme);
        var bytes = Encoding.UTF8.GetBytes(text);
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
        while (reader.Read()) {
            if (reader.CurrentDepth != 1 || reader.TokenType != JsonTokenType.PropertyName || !reader.ValueTextEquals(property)) continue;
            reader.Read();
            int start = checked((int)reader.TokenStartIndex), end = checked((int)reader.BytesConsumed);
            return Encoding.UTF8.GetString(bytes, 0, start) + encoded + Encoding.UTF8.GetString(bytes, end, bytes.Length - end);
        }
        int closing = text.LastIndexOf('}');
        string before = text[..closing].TrimEnd();
        string comma = parsed.Count > 0 && !before.EndsWith(',') ? "," : "";
        string updated = text.Insert(closing, comma + "\n  " + JsonSerializer.Serialize(property) + ": " + encoded + "\n");
        if (JsonNode.Parse(updated, documentOptions: Options)?[property]?.GetValue<string>() != theme) throw new InvalidDataException("Could not update the theme safely.");
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

    // Every app with a theme setting rotates together: SSMS plus the VS Code
    // family (Kiro, VS Code, Cursor, Windsurf, VSCodium). Returns profiles set.
    public static int Configure(Action<Exception> log, bool light, bool rotate) {
        var activeNames = new List<string>();
        int configured = ConfigureSsms(log, light, rotate, activeNames) + ConfigureEditors(log, light, rotate, activeNames);
        CurrentThemeNames = activeNames.ToArray();
        return configured;
    }

    private static int ConfigureSsms(Action<Exception> log, bool light, bool rotate, List<string> activeNames) {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "SSMS");
        if (!Directory.Exists(root)) return 0;
        var themes = InstalledThemes();
        if (themes.Count == 0) return 0;
        int configured = 0;
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
                activeNames.Add("SSMS: " + selected.Name);
            } catch (Exception ex) { log(ex); }
        }
        return configured;
    }

    // Settings folder under %APPDATA%, extensions folder under the user profile,
    // and install folder names under %LOCALAPPDATA%\Programs or Program Files.
    private sealed record Editor(string Name, string SettingsFolder, string ExtensionsFolder, string[] InstallFolders);
    private static readonly Editor[] Editors = {
        new("Kiro", "Kiro", ".kiro", new[] { "Kiro" }),
        new("VS Code", "Code", ".vscode", new[] { "Microsoft VS Code" }),
        new("VS Code Insiders", "Code - Insiders", ".vscode-insiders", new[] { "Microsoft VS Code Insiders" }),
        new("Cursor", "Cursor", ".cursor", new[] { "cursor", "Cursor" }),
        new("Windsurf", "Windsurf", ".windsurf", new[] { "Windsurf" }),
        new("VSCodium", "VSCodium", ".vscode-oss", new[] { "VSCodium" }),
    };
    // Used only when an editor's theme list can't be read (Kiro's previous rotation).
    private static readonly Theme[] KiroFallback = {
        new("Kiro Light", "Kiro Light", true), new("Light+", "Light+", true), new("Quiet Light", "Quiet Light", true), new("Solarized Light", "Solarized Light", true),
        new("Kiro Dark", "Kiro Dark", false), new("Dark+", "Dark+", false), new("Abyss", "Abyss", false), new("Kimbie Dark", "Kimbie Dark", false),
        new("Monokai", "Monokai", false), new("Monokai Dimmed", "Monokai Dimmed", false), new("Solarized Dark", "Solarized Dark", false), new("Tomorrow Night Blue", "Tomorrow Night Blue", false),
    };

    // Reads contributes.themes from one extension's package.json. High-contrast
    // themes are skipped; the setting value is the theme id, else its label.
    public static IEnumerable<Theme> ExtensionThemes(string packageJson) {
        JsonNode root;
        try { root = JsonNode.Parse(packageJson, documentOptions: Options); } catch (JsonException) { yield break; }
        if (root?["contributes"]?["themes"] is not JsonArray themes) yield break;
        foreach (var theme in themes) {
            string ui = theme?["uiTheme"]?.GetValueKind() == JsonValueKind.String ? theme["uiTheme"].GetValue<string>() : null;
            if (ui is not ("vs" or "vs-dark")) continue;
            string id = theme["id"]?.GetValueKind() == JsonValueKind.String ? theme["id"].GetValue<string>() : null;
            string label = theme["label"]?.GetValueKind() == JsonValueKind.String ? theme["label"].GetValue<string>() : null;
            string name = !string.IsNullOrWhiteSpace(id) ? id : label;
            if (string.IsNullOrWhiteSpace(name) || name.StartsWith('%')) continue;
            yield return new Theme(name, name, ui == "vs");
        }
    }

    private static IReadOnlyList<Theme> EditorThemes(Editor editor) {
        var folders = new List<string> { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), editor.ExtensionsFolder, "extensions") };
        foreach (string install in editor.InstallFolders)
            foreach (string parent in new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) })
                folders.Add(Path.Combine(parent, install, "resources", "app", "extensions"));
        var themes = new List<Theme>();
        foreach (string folder in folders.Where(Directory.Exists))
            foreach (string extension in Directory.EnumerateDirectories(folder)) {
                string package = Path.Combine(extension, "package.json");
                if (File.Exists(package)) themes.AddRange(ExtensionThemes(File.ReadAllText(package)));
            }
        return themes.DistinctBy(theme => theme.Id).ToArray();
    }

    private static int ConfigureEditors(Action<Exception> log, bool light, bool rotate, List<string> activeNames) {
        int configured = 0;
        foreach (var editor in Editors) {
            string user = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), editor.SettingsFolder, "User");
            if (!Directory.Exists(user)) continue;
            try {
                var themes = EditorThemes(editor);
                if (!themes.Any(theme => theme.Light == light)) themes = editor.Name == "Kiro" ? KiroFallback : themes;
                if (!themes.Any(theme => theme.Light == light)) continue;
                string path = Path.Combine(user, "settings.json");
                string original = File.Exists(path) ? File.ReadAllText(path) : "{}";
                if (string.IsNullOrWhiteSpace(original)) original = "{}";
                var json = JsonNode.Parse(original, documentOptions: Options);
                string current = json?["workbench.colorTheme"]?.GetValueKind() == JsonValueKind.String ? json["workbench.colorTheme"].GetValue<string>() : null;
                // A theme we can't classify (light or dark) is left alone until the next rotation.
                if (!rotate && current != null && !themes.Any(theme => theme.Id == current)) { configured++; activeNames.Add(editor.Name + ": " + current); continue; }
                Theme selected = themes.FirstOrDefault(theme => theme.Light == light && theme.Id == current);
                if (rotate || selected == null) {
                    var choices = themes.Where(theme => theme.Light == light && theme.Id != current).ToArray();
                    if (choices.Length == 0) choices = themes.Where(theme => theme.Light == light).ToArray();
                    selected = choices[Random.Shared.Next(choices.Length)];
                }
                string updated = SetProperty(original, "workbench.colorTheme", selected.Id);
                // With "auto detect color scheme" on, the editor reads the preferred theme instead.
                if (json?["window.autoDetectColorScheme"]?.GetValueKind() == JsonValueKind.True)
                    updated = SetProperty(updated, light ? "workbench.preferredLightColorTheme" : "workbench.preferredDarkColorTheme", selected.Id);
                if (updated != original) {
                    if (File.Exists(path) && !File.Exists(path + ".3EWindows-theme.bak")) File.Copy(path, path + ".3EWindows-theme.bak");
                    File.WriteAllText(path + ".3e.tmp", updated, new UTF8Encoding(false));
                    File.Move(path + ".3e.tmp", path, true);
                }
                configured++;
                activeNames.Add(editor.Name + ": " + selected.Name);
            } catch (Exception ex) { log(ex); }
        }
        return configured;
    }
}
