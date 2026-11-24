using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace ThreeFingerDragOnWindows;

// Installation is separate from an installed module's on/off preference. Built-in
// modules keep their payload and preferences so they can be installed again offline.
internal sealed class HubModules {
    public const string Phone = "Track Phone", Tab = "Track Tab", Car = "Car View",
        Drag = "Three-finger drag", Clicks = "Clicks keyboard", Mac = "Mac keyboard layout",
        PowerToys = "PowerToys", Kalista = "Kalista", Mouse = "Mouse",
        Wallpaper = "Dynamic wallpaper", AutoDark = "Auto dark";
    public static readonly IReadOnlyList<string> All = Array.AsReadOnly(new[] {
        Phone, Tab, Car, Drag, Clicks, Mac, PowerToys, Kalista, Mouse, Wallpaper, AutoDark
    });
    private readonly List<string> uninstalled;
    public bool Busy { get; private set; }

    public HubModules(List<string> uninstalled) => this.uninstalled = uninstalled;
    public bool IsInstalled(string id) => !uninstalled.Contains(id);

    public HubMenuSubmenu CreateMenu(Action<string, bool> change, bool enabled = true) {
        var menu = new HubMenuSubmenu { Text = "Modules", IsEnabled = enabled && !Busy };
        foreach (string id in All) {
            bool install = !IsInstalled(id);
            menu.Items.Add(new HubMenuItem {
                Text = (install ? "Install " : "Uninstall ") + id,
                IsEnabled = menu.IsEnabled,
                Command = new HubMenuCommand(() => change(id, install))
            });
        }
        return menu;
    }

    public async Task ChangeAsync(string id, bool install, Func<string, Task> stop, Action save) {
        if (!All.Contains(id)) throw new ArgumentException("Unknown module.", nameof(id));
        if (Busy || IsInstalled(id) == install) return;
        Busy = true;
        try {
            // Stop and restore any input/display leases before hiding a module.
            // A failed stop leaves it installed and available for recovery.
            if (!install) await stop(id);
            if (install) uninstalled.RemoveAll(value => value == id); else uninstalled.Add(id);
            try { save(); }
            catch {
                if (install) uninstalled.Add(id); else uninstalled.RemoveAll(value => value == id);
                throw;
            }
        } finally { Busy = false; }
    }
}
