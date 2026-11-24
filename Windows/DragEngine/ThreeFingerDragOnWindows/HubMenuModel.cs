using System;
using System.Collections.Generic;
using System.Windows.Input;

namespace ThreeFingerDragOnWindows;

// State for the Win32 menu, not XAML elements. Keeping hidden MenuFlyoutItems here
// attaches native-only commands to WinUI's thread-affine lifetime and flyout plumbing.
internal sealed class HubMenuModel {
    public List<HubMenuItem> Items { get; } = new();

    // Preorder matches the native menu's command IDs, including submenu parents.
    public static IEnumerable<HubMenuItem> Flatten(IEnumerable<HubMenuItem> items) {
        foreach (var item in items) {
            yield return item;
            if (item is HubMenuSubmenu submenu)
                foreach (var child in Flatten(submenu.Items)) yield return child;
        }
    }
}

internal class HubMenuItem {
    public string Text { get; set; }
    public bool IsEnabled { get; set; } = true;
    public ICommand Command { get; set; }
    public object CommandParameter { get; set; }
}

internal sealed class HubMenuToggleItem : HubMenuItem {
    public bool IsChecked { get; set; }
}

internal sealed class HubMenuSeparator : HubMenuItem { }

internal sealed class HubMenuSubmenu : HubMenuItem {
    public List<HubMenuItem> Items { get; } = new();
}

internal sealed class HubMenuCommand : ICommand {
    private readonly Action action;
    public HubMenuCommand(Action action) => this.action = action;
    public event EventHandler CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object parameter) => true;
    public void Execute(object parameter) => action();
}
