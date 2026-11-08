// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

// Coordinates are fractions of the pad. Keep the phone's four-finger branch
// in Web/PhoneTrackpad.js and the shared gesture fixtures in sync with this.
public sealed class TrackTabGesture(Action<string, int> emit) {
    public readonly record struct Contact(int Id, double X, double Y);
    private Contact[] origin;
    private double originX, originY, radius, stepX, travel;
    private long started, switched;
    private bool claimed, switching, done, ending;
    public bool Claimed => claimed;

    public void Update(Contact[] contacts, long now) {
        if (contacts.Length == 0) { Finish(now, true); return; }
        if (contacts.Length > 4) { claimed = done = true; EndApps(); return; }
        if (contacts.Length != 4) { if (claimed) { done |= switching; EndApps(); ending = true; } return; }
        claimed = true;
        if (done || ending) return;
        if (origin == null) {
            origin = contacts.ToArray(); started = now;
            originX = contacts.Average(p => p.X); originY = contacts.Average(p => p.Y);
            radius = contacts.Average(p => Math.Sqrt(Math.Pow(p.X-originX,2)+Math.Pow(p.Y-originY,2)));
            stepX = originX; return;
        }
        if (contacts.Any(p => !origin.Any(o => o.Id == p.Id))) { Cancel(); claimed = done = true; return; }
        double cx = contacts.Average(p => p.X), cy = contacts.Average(p => p.Y);
        double x = cx-originX, y = cy-originY;
        travel = Math.Max(travel, contacts.Max(p => { var o=origin.First(o=>o.Id==p.Id); return Math.Sqrt(Math.Pow(p.X-o.X,2)+Math.Pow(p.Y-o.Y,2)); }));
        if (switching) {
            if (now-switched >= 200 && Math.Abs(cx-stepX) >= .07) {
                emit("appsStep", Math.Sign(cx-stepX)); stepX = cx; switched = now;
            }
            return;
        }
        double spread = contacts.Average(p => Math.Sqrt(Math.Pow(p.X-cx,2)+Math.Pow(p.Y-cy,2))) - radius;
        // Opposing motion distinguishes a pinch from interleaved finger samples
        // in a fast swipe (one finger may arrive a frame before the others).
        bool opposingX = contacts.Any(p=>p.X-origin.First(o=>o.Id==p.Id).X>.012) && contacts.Any(p=>p.X-origin.First(o=>o.Id==p.Id).X<-.012);
        bool opposingY = contacts.Any(p=>p.Y-origin.First(o=>o.Id==p.Id).Y>.012) && contacts.Any(p=>p.Y-origin.First(o=>o.Id==p.Id).Y<-.012);
        if (Math.Abs(spread)>=.025 && Math.Abs(spread)>Math.Sqrt(x*x+y*y)*.65 && (opposingX||opposingY)) {
            done = true; emit("shortcut",spread<0?0:1);
        } else if (Math.Abs(x)>=.07 && Math.Abs(x)>Math.Abs(y)*1.3) {
            switching = true; stepX = cx; switched = now; emit("appsBegin",Math.Sign(x));
        } else if (Math.Abs(y)>=.09 && Math.Abs(y)>Math.Abs(x)*1.3) {
            done = true; emit(y<0?"taskView":"showDesktop",0);
        }
    }

    private void EndApps() { if (switching) { switching=false; emit("appsEnd",0); } }
    private void Finish(long now, bool tap) {
        bool window = tap && origin!=null && !done && !switching && travel<.025 && now-started<=350;
        EndApps(); origin=null; claimed=done=ending=false; travel=0;
        if(window)emit("appWindow",1);
    }
    public void Cancel() => Finish(0,false);
}
