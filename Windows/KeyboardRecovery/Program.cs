using System;
using System.Diagnostics;
using System.IO;
using ThreeFingerDragOnWindows;

try {
    string lease = null;
    if (args.Length == 2 && int.TryParse(args[0], out int owner)) {
        lease = args[1];
        try { using var process = Process.GetProcessById(owner); await process.WaitForExitAsync(); }
        catch (ArgumentException) { }
    } else if (args.Length != 1 || args[0] != "--restore") return 2;
    await MacKeyboardLayout.Create().DisableAsync(lease);
    return 0;
} catch (Exception ex) {
    var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "3EWindows");
    Directory.CreateDirectory(data);
    File.AppendAllText(Path.Combine(data, "hub.log"), "Keyboard restoration: " + ex + Environment.NewLine);
    return 1;
}
