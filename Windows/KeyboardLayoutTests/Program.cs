using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ThreeFingerDragOnWindows;

int count = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); Console.WriteLine("PASS: " + name); count++; }
string template = Path.Combine(AppContext.BaseDirectory, "MacKeyboard.json");
string json = File.ReadAllText(template);
var normal = MacKeyboardLayout.Profile(json, false);
var swapped = MacKeyboardLayout.Profile(json, true);
bool Maps(JsonObject p, string from, string to, string section = "remapKeys", string group = "inProcess") =>
    p[section][group].AsArray().Any(k => (string)k["originalKeys"] == from && (string)k["newRemapKeys"] == to);
Check(Maps(normal,"164","162") && Maps(normal,"162","164"), "PC modifiers swap only in the temporary profile");
Check(!Maps(swapped,"164","162") && !Maps(swapped,"162","164"), "Existing registry swap is not applied twice");
Check(Maps(normal,"163","162") && Maps(swapped,"163","162"), "Clicks Command bypasses the left modifier swap");
foreach (var pair in new[] { ("17;9","164;9"), ("17;81","164;115"), ("17;32","91;83"), ("17;16;90","162;89"), ("17;16;51","91;44"), ("17;16;52","91;160;83"), ("17;16;53","91;160;83") })
    Check(Maps(normal,pair.Item1,pair.Item2,"remapShortcuts","global"), "Command shortcut " + pair.Item1 + " → " + pair.Item2);
Check(normal["remapShortcuts"]["global"].AsArray().Count(k => (string)k["originalKeys"] == "17;16;90") == 1,
    "Either Shift can invoke redo without duplicate source bindings");
byte[] legacy = [0,0,0,0,0,0,0,0,3,0,0,0,0x1D,0,0x38,0,0x38,0,0x1D,0,0,0,0,0];
Check(MacKeyboardLayout.ContainsLegacySwap(legacy) && !MacKeyboardLayout.ContainsLegacySwap(null), "Legacy scan-map detection is read-only");
legacy[16] = 0;
try { MacKeyboardLayout.ContainsLegacySwap(legacy); throw new Exception("Accepted partial swap"); }
catch (InvalidOperationException) { Check(true,"Partial pre-existing swaps fail safely"); }

string root = Path.Combine(AppContext.BaseDirectory,"test-data",Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try {
    string kb = Path.Combine(root,"Keyboard Manager"), data = Path.Combine(root,"3e");
    Directory.CreateDirectory(kb);
    string settings = Path.Combine(kb,"settings.json"), journal = Path.Combine(data,"mac-keyboard-lease.json");
    byte[] original = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Encoding.UTF8.GetBytes("{\n  \"name\":\"Keyboard Manager\",\"properties\":{\"activeConfiguration\":{\"value\":\"borrowed\"}},\"unrelated\":42\n}")).ToArray();
    File.WriteAllBytes(settings,original);
    string custom = Path.Combine(kb,"borrowed.json"); File.WriteAllText(custom,"personal mappings");
    var engine = new FakeEngine { Running = true };
    MacKeyboardLayout Layout() => new(kb,data,template,engine,()=>false);
    var layout = Layout();
    await layout.EnableAsync();
    string firstLease = engine.Leases.Last();
    Check(layout.Active && File.Exists(journal),"Enable starts the engine and journals the original settings");
    Check(File.ReadAllText(custom)=="personal mappings","Personal profile contents are never overwritten");
    Check(JsonNode.Parse(File.ReadAllText(settings))["properties"]["activeConfiguration"]["value"].GetValue<string>().StartsWith("3e-mac-"),"Enable selects a separate profile");
    await layout.EnableAsync();
    Check(engine.Leases.Count==1,"Repeated enable keeps one crash watcher per app instance");
    engine.Running=false;
    await layout.EnsureAsync();
    Check(layout.Active,"Recovery restarts a stopped engine without losing the original snapshot");
    // A replacement app must adopt the old snapshot, not snapshot its own profile.
    var replacement=Layout(); await replacement.EnsureAsync();
    await layout.DisableAsync(firstLease);
    Check(replacement.Active,"An old crash watcher cannot disable a replacement app's lease");
    await replacement.DisableAsync();
    Check(File.ReadAllBytes(settings).SequenceEqual(original) && engine.Running && !File.Exists(journal),"OFF restores exact original bytes and a previously running engine");
    Check(Directory.GetFiles(kb,"3e-mac-*.json").Length==0,"OFF removes only the temporary profile");
    await replacement.DisableAsync();
    Check(File.ReadAllBytes(settings).SequenceEqual(original),"Repeated OFF is harmless");

    File.Delete(settings); engine.Running=false;
    await layout.EnableAsync(); await layout.DisableAsync();
    Check(!File.Exists(settings) && !engine.Running,"A computer with no keyboard settings or engine returns to that state");
    File.WriteAllBytes(settings,original); engine.Running=true; engine.FailNextStart=true;
    try { await layout.EnableAsync(); throw new Exception("Expected startup failure"); }
    catch (IOException) { }
    Check(File.ReadAllBytes(settings).SequenceEqual(original) && engine.Running && !File.Exists(journal),"Failed activation rolls back settings and restores the previous engine");

    await layout.EnableAsync(); engine.FailNextStart=true;
    try { await layout.DisableAsync(); throw new Exception("Expected restoration failure"); }
    catch (IOException) { }
    Check(File.Exists(journal) && File.ReadAllBytes(settings).SequenceEqual(original),"A failed engine restoration retains the original journal for retry");
    await layout.DisableAsync();
    Check(engine.Running && !File.Exists(journal),"Retry completes a pending restoration");

    await layout.EnableAsync();
    // Equivalent to a watcher after a forced process exit, using only fake input.
    await Layout().DisableAsync(engine.Leases.First());
    Check(File.ReadAllBytes(settings).SequenceEqual(original) && !File.Exists(journal),"Crash recovery restores the original keyboard configuration");
    Check(File.ReadAllText(custom)=="personal mappings","Custom profile survives enable, restart, failure, and crash recovery");
} finally { Directory.Delete(root,true); }
Console.WriteLine($"PASS: {count} keyboard layout checks; no live input or system settings used.");

sealed class FakeEngine : MacKeyboardLayout.IEngine {
    public bool Running { get; set; }
    public bool FailNextStart;
    public List<string> Leases = new();
    public void Validate() { }
    public Task StopAsync() { Running=false; return Task.CompletedTask; }
    public Task StartAsync(bool owned) {
        if (FailNextStart) { FailNextStart=false; throw new IOException("simulated startup failure"); }
        Running=true; return Task.CompletedTask;
    }
    public void Watch(string lease) => Leases.Add(lease);
}
