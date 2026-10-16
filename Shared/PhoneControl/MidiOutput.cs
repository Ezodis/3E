// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

public record MidiPort(int id, string name);
public abstract class MidiOutput : IDisposable {
    private readonly HashSet<int> notes = new();
    public int Selected { get; private set; } = -1;
    public string Status { get; protected set; } = "Choose a MIDI output";
    public abstract MidiPort[] Ports();
    protected abstract void Open(int id);
    protected abstract void Close();
    protected abstract void Write(byte status, byte number, byte value);
    public void Select(int id) {
        Panic(); Close(); Selected = -1;
        if (id < 0) { Status = "MIDI off"; return; }
        try {
            var port = Ports().FirstOrDefault(p => p.id == id) ?? throw new InvalidOperationException("MIDI output is unavailable");
            Open(id); Selected = id; Status = port.name;
        } catch (Exception ex) { Status = ex.Message; }
    }
    public void Send(bool note, int channel, int number, int value) {
        if (Selected < 0) return;
        try {
            Write((byte)((note ? 0x90 : 0xB0) | channel),(byte)number,(byte)value);
            if (note) { int key = channel*128+number; if (value > 0) notes.Add(key); else notes.Remove(key); }
        } catch (Exception ex) { Status = ex.Message; Panic(); Close(); Selected = -1; }
    }
    // Release only notes originating here; never silence other controllers' notes.
    public void Panic() {
        foreach (var key in notes.ToArray()) try { Write((byte)(0x80 | key/128),(byte)(key%128),0); } catch { }
        notes.Clear();
    }
    public object Info() => new { ports = Ports(), selected = Selected, status = Status };
    public void Dispose() { Panic(); Close(); Selected = -1; }
}
