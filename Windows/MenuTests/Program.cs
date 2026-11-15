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
