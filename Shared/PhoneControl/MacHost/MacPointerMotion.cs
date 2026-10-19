// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneHost;

// Quartz posts asynchronously. Accumulate from the newest submitted target
// while the observed cursor is still at an earlier target, instead of losing
// deltas. Physical pointer movement, screen-edge clamping and idle time rebase.
public sealed class MacPointerMotion {
    private readonly List<(double X,double Y)> pending=new();
    private (double X,double Y) origin;
    private long lastMove;
    public void Reset()=>pending.Clear();
    public (double X,double Y) Resolve(double x,double y,long now) {
        var observed=(X:x,Y:y);
        if(pending.Count==0)return observed;
        if(now-lastMove>100) {Reset();return observed;}
        int acknowledged=pending.FindLastIndex(p=>Math.Abs(p.X-x)<0.5&&Math.Abs(p.Y-y)<0.5);
        if(acknowledged>=0) {
            origin=pending[acknowledged];pending.RemoveRange(0,acknowledged+1);
        } else if(Math.Abs(origin.X-x)>=0.5||Math.Abs(origin.Y-y)>=0.5) {
            Reset();return observed;
        }
        return pending.Count==0?observed:pending[^1];
    }
    public (double X,double Y) Move(double x,double y,int dx,int dy,long now) {
        var start=Resolve(x,y,now);
        if(pending.Count==0)origin=(x,y);
        var target=(X:start.X+dx,Y:start.Y+dy);
        pending.Add(target);lastMove=now;
        // Bound state even if the OS stops acknowledging events.
        if(pending.Count>64) {origin=pending[0];pending.RemoveAt(0);}
        return target;
    }
}
