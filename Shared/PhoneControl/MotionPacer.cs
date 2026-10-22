// SPDX-License-Identifier: MIT
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ThreeE.PhoneControl;

// Phone Wi-Fi does not deliver packets evenly: a radio waking from power save
// hands over several 8 ms pointer packets at once. Applying each clump
// immediately makes the pointer jump. Every move carries the phone's own
// timestamp, so the computer replays motion at the finger's pace.
//
// The replay delay adapts to the network: on a steady link it is zero (moves
// apply on arrival), and it only grows (up to MaxPlayout) by as much jitter as
// is actually measured. A new gesture after a pause always starts immediately.
// Clicks, presses and every other command first apply all pending motion, so
// a click never lands before the motion that preceded it.
public sealed class MotionPacer : IDisposable {
    public const double MaxPlayout = 40, ResetGap = 300;
    private const int MaxQueued = 64;

    // Pure scheduling (no threads, injectable times) so it can be tested.
    public sealed class Schedule {
        private double offset = double.NaN, jitter, lastArrival = double.NegativeInfinity;
        public double Playout => Math.Clamp(jitter, 0, MaxPlayout);
        // Host time at which a move stamped phoneTime should be applied.
        public double Due(double phoneTime, double hostNow) {
            double sample = hostNow - phoneTime; // one-way delay + clock offset
            if (double.IsNaN(offset) || hostNow - lastArrival > ResetGap) { offset = sample; jitter = 0; }
            else if (sample < offset) offset = sample;            // fastest delivery seen
            else offset += (sample - offset) * 0.005;             // follow slow clock drift
            lastArrival = hostNow;
            // Peak lateness, fading about 1% per packet (~1-2 s): covers a whole
            // clump with one steady delay, then shrinks again on a calm link.
            jitter = Math.Max(Math.Max(0, sample - offset), jitter * 0.99);
            return phoneTime + offset + Playout;
        }
    }

    private readonly object gate;
    private readonly Action<int, int> apply;
    private readonly Schedule schedule = new();
    private readonly Queue<(double due, int x, int y)> queue = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly AutoResetEvent wake = new(false);
    private readonly Thread thread;
    private volatile bool disposed;
    private bool fineTimer;

    // gate: the receiver's input lock (moves apply under it, like every other
    // command). apply: moves the pointer.
    public MotionPacer(object gate, Action<int, int> apply) {
        this.gate = gate; this.apply = apply;
        thread = new Thread(Run) { IsBackground = true, Name = "3E pointer pacer", Priority = ThreadPriority.AboveNormal };
        thread.Start();
    }

    public double Now => clock.Elapsed.TotalMilliseconds;

    // Call while holding gate.
    public void Move(int x, int y, double phoneTime) {
        double now = Now, due;
        lock (queue) {
            due = schedule.Due(phoneTime, now);
            if (queue.Count > 0 || due > now + 0.5) {
                if (queue.Count >= MaxQueued) DrainLocked();
                queue.Enqueue((due, x, y));
                wake.Set();
                return;
            }
        }
        apply(x, y);
    }

    // Applies all pending motion now. Call while holding gate, before any
    // other command, so input stays in order.
    public void Flush() { lock (queue) DrainLocked(); }

    // Drops pending motion (the phone disconnected or released).
    public void Clear() { lock (queue) queue.Clear(); }

    private void DrainLocked() {
        while (queue.Count > 0) { var (_, x, y) = queue.Dequeue(); try { apply(x, y); } catch { } }
    }

    private void Run() {
        while (!disposed) {
            double wait;
            lock (gate) {
                lock (queue) {
                    double now = Now;
                    while (queue.Count > 0 && queue.Peek().due <= now) { var (_, x, y) = queue.Dequeue(); try { apply(x, y); } catch { } }
                    wait = queue.Count > 0 ? queue.Peek().due - now : -1;
                }
            }
            if (wait < 0) { FineTimer(false); wake.WaitOne(); continue; }
            FineTimer(true);
            if (wait > 1.5) Thread.Sleep(1); else Thread.SpinWait(200);
        }
        FineTimer(false);
    }

    // Windows sleeps in ~15.6 ms steps by default; ask for 1 ms only while
    // motion is being paced.
    private void FineTimer(bool on) {
        if (on == fineTimer || !OperatingSystem.IsWindows()) return;
        fineTimer = on;
        try { if (on) TimeBeginPeriod(1); else TimeEndPeriod(1); } catch { }
    }
    [DllImport("winmm.dll", EntryPoint = "timeBeginPeriod")] private static extern uint TimeBeginPeriod(uint period);
    [DllImport("winmm.dll", EntryPoint = "timeEndPeriod")] private static extern uint TimeEndPeriod(uint period);

    public void Dispose() {
        if (disposed) return;
        disposed = true;
        wake.Set();
        thread.Join(500);
        wake.Dispose();
    }
}
