using System;
using Microsoft.UI.Xaml.Input;

namespace ThreeFingerDragOnWindows;

internal static class TrayCommandBridge {
    // The tray control stores commands in WinRT dependency properties. Use its
    // native command type at that boundary; native menu snapshots stay managed.
    public static XamlUICommand Create(Action action) {
        var command = new XamlUICommand();
        command.ExecuteRequested += (_, _) => action();
        return command;
    }
}
