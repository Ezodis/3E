using System.Collections.Concurrent;
using System.Diagnostics;
using Windows.Storage;

namespace ThreeFingerDragOnWindows.utils;

using System;
using System.IO;
using System.Threading.Tasks;

public class Logger {
    public static void Fatal(Exception error) {
        try {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "crash.log");
            if (File.Exists(path) && new FileInfo(path).Length > 65536) File.WriteAllText(path, "");
            File.AppendAllText(path, DateTimeOffset.Now.ToString("O") + " " + WindowsHub.Version + " " + error + Environment.NewLine);
        } catch { }
    }
    private static readonly ConcurrentQueue<string> _logMessages = new();
    private static readonly int _maxLogCount = 10000;

    public static void Log(string message){
        Debug.WriteLine(message);
        if(App.SettingsData != null && !App.SettingsData.RecordLogs){
            return;
        }
        
        string timestamp = DateTime.Now.ToString("HH:mm:ss.fff");
        string logEntry = $"[{timestamp}] {message}";

        if(_logMessages.Count >= _maxLogCount){
            _logMessages.TryDequeue(out _);
        }
        _logMessages.Enqueue(logEntry);
    }

    public static Task ExportLogsAsync(string path){
        return File.WriteAllLinesAsync(path, _logMessages.ToArray());
    }
}
