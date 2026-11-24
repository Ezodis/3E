using ThreeFingerDragOnWindows;

// Deliberately has no Windows/WinUI reference: native menu state must not retain
// DependencyObjects that can be accessed/finalized on a different apartment.
var model = new HubMenuModel();
int calls = 0;
var toggle = new HubMenuToggleItem { Text = "LoL macros", IsChecked = true };
toggle.Command = new HubMenuCommand(() => { toggle.IsChecked = !toggle.IsChecked; calls++; });
model.Items.Add(toggle);
model.Items.Add(new HubMenuSeparator());
var snapshot = model.Items.ToArray();
model.Items.Clear();
model.Items.Add(new HubMenuItem { Text = "A refreshed menu", IsEnabled = false });
if (snapshot.Length != 2 || snapshot[0] != toggle || snapshot[1] is not HubMenuSeparator)
    throw new Exception("Refreshing the menu invalidated an in-flight selection.");
await Task.Run(() => {
    for (int i = 0; i < 100; i++) {
        if (!toggle.Command.CanExecute(toggle.CommandParameter)) throw new Exception("Command unavailable.");
        toggle.Command.Execute(toggle.CommandParameter);
        GC.Collect();
        GC.WaitForPendingFinalizers();
    }
});
if (calls != 100 || !toggle.IsChecked) throw new Exception("Toggle state or command count changed.");
if (model.Items[0].IsEnabled || model.Items[0].Text != "A refreshed menu")
    throw new Exception("Selection mutated the next menu's state.");
Console.WriteLine("Native menu state/command/lifetime checks passed (100 cross-thread toggles).");

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
var removed = new List<string>();
var modules = new HubModules(removed);
int stops = 0, saves = 0;
foreach (string id in HubModules.All) {
    Check(modules.IsInstalled(id), id + " missing from existing installations.");
    string selectedId = null;
    bool selectedInstall = true;
    var manage = modules.CreateMenu((name, install) => { selectedId = name; selectedInstall = install; });
    var action = manage.Items.Single(item => item.Text == "Uninstall " + id);
    action.Command.Execute(null);
    Check(selectedId == id && !selectedInstall, "Uninstall action targeted the wrong module.");
    await modules.ChangeAsync(id, false, name => {
        Check(name == id && modules.IsInstalled(id), "Module hidden before cleanup completed.");
        stops++; return Task.CompletedTask;
    }, () => saves++);
    Check(!modules.IsInstalled(id), "Removed module remains installed: " + id);
    // An app restart reloads the same JSON-backed installation state.
    var restored = new HubModules(System.Text.Json.JsonSerializer.Deserialize<List<string>>(
        System.Text.Json.JsonSerializer.Serialize(removed))!);
    Check(!restored.IsInstalled(id), "Restart lost the removal: " + id);
    manage = modules.CreateMenu((name, install) => { selectedId = name; selectedInstall = install; });
    manage.Items.Single(item => item.Text == "Install " + id).Command.Execute(null);
    Check(selectedId == id && selectedInstall, "Install action targeted the wrong module.");
    await modules.ChangeAsync(id, true, _ => throw new Exception("Install must not run removal."), () => saves++);
    Check(modules.IsInstalled(id) && !removed.Contains(id), "Reinstall failed: " + id);
}
Check(stops == HubModules.All.Count && saves == stops * 2, "Module lifecycle ran twice or missed persistence.");

// Removal is asynchronous for keyboard restoration and macro shutdown. Do not
// hide a still-running module or permit a conflicting second operation.
var cleanup = new TaskCompletionSource();
var pending = modules.ChangeAsync(HubModules.Mac, false, _ => cleanup.Task, () => saves++);
Check(modules.Busy && modules.IsInstalled(HubModules.Mac), "Pending cleanup hid the module.");
Check(!modules.CreateMenu((_, _) => { }).IsEnabled, "Module changes available during cleanup.");
await modules.ChangeAsync(HubModules.Car, false, _ => throw new Exception("Concurrent removal ran."), () => saves++);
cleanup.SetException(new InvalidOperationException("Keyboard restoration failed"));
try { await pending; throw new Exception("Failed cleanup was ignored."); }
catch (InvalidOperationException) { }
Check(!modules.Busy && modules.IsInstalled(HubModules.Mac), "Failed cleanup stranded a hidden module.");
try {
    await modules.ChangeAsync(HubModules.AutoDark, false, _ => Task.CompletedTask, () => throw new System.IO.IOException());
    throw new Exception("Failed persistence was ignored.");
} catch (System.IO.IOException) { }
Check(modules.IsInstalled(HubModules.AutoDark), "A failed save committed removal only in memory.");

var submenu = modules.CreateMenu((name, install) => { });
var last = new HubMenuItem { Text = "Quit" };
var flat = HubMenuModel.Flatten(new HubMenuItem[] { toggle, submenu, last }).ToArray();
Check(flat.Length == HubModules.All.Count + 3 && flat[1] == submenu && flat[^1] == last,
    "Native command IDs no longer match the menu snapshot.");
Check(flat.Skip(2).Take(HubModules.All.Count).SequenceEqual(submenu.Items), "Submenu commands have wrong IDs.");
Console.WriteLine($"Module lifecycle, persistence, failed cleanup and nested command checks passed ({HubModules.All.Count} modules).");
