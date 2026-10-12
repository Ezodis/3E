using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ThreeFingerDragOnWindows;

public static class SsmsTheme {
    public const string ThemeProperty = "environment.visualExperience.colorTheme";
    private static readonly JsonDocumentOptions Options = new() { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true };

    // SSMS 22 uses the Visual Studio JSON settings store. Change just this value;
    // keep comments, connection settings and other options intact.
    public static string FollowSystem(string text) {
        var parsed = JsonNode.Parse(text, documentOptions: Options)?.AsObject() ?? throw new InvalidDataException("Invalid SSMS settings.");
        if (parsed[ThemeProperty]?.GetValue<string>() == "system") return text;
        var bytes = Encoding.UTF8.GetBytes(text);
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
        while (reader.Read()) {
            if (reader.CurrentDepth != 1 || reader.TokenType != JsonTokenType.PropertyName || !reader.ValueTextEquals(ThemeProperty)) continue;
            reader.Read();
            int start = checked((int)reader.TokenStartIndex), end = checked((int)reader.BytesConsumed);
            return Encoding.UTF8.GetString(bytes, 0, start) + "\"system\"" + Encoding.UTF8.GetString(bytes, end, bytes.Length - end);
        }
        int closing = text.LastIndexOf('}');
        string before = text[..closing].TrimEnd();
        string comma = parsed.Count > 0 && !before.EndsWith(',') ? "," : "";
        string updated = text.Insert(closing, comma + "\n  \"" + ThemeProperty + "\": \"system\"\n");
        if (JsonNode.Parse(updated, documentOptions: Options)?[ThemeProperty]?.GetValue<string>() != "system") throw new InvalidDataException("Could not update SSMS theme safely.");
        return updated;
    }

    public static int Configure(Action<Exception> log) {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "SSMS");
        if (!Directory.Exists(root)) return 0;
        int configured = 0;
        foreach (string profile in Directory.EnumerateDirectories(root, "22.*")) {
            string path = Path.Combine(profile, "settings.json");
            if (!File.Exists(path)) continue;
            try {
                string original = File.ReadAllText(path), updated = FollowSystem(original);
                if (updated != original) {
                    if (!File.Exists(path + ".3EWindows-theme.bak")) File.Copy(path, path + ".3EWindows-theme.bak");
                    File.WriteAllText(path + ".3e.tmp", updated, new UTF8Encoding(false));
                    File.Move(path + ".3e.tmp", path, true);
                }
                configured++;
            } catch (Exception ex) { log(ex); }
        }
        return configured;
    }
}
