// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneHost;

// Quartz cursor observations can lag or fall between posted targets. During
// continuous phone motion, integrate from our last target, never that feedback.
// After a pause, yield to the physical mouse. Clamp before retaining a target so
// pushing against an edge cannot build up invisible movement to undo later.
public sealed class MacPointerMotion {
    public readonly record struct Display(double X,double Y,double Width,double Height);
    private readonly Func<double,double,(double X,double Y)> clamp;
    private (double X,double Y)? target;
    private long lastMove;
    public MacPointerMotion(Func<double,double,(double X,double Y)> clamp=null) {
        this.clamp=clamp??((x,y)=>(x,y));
    }
    public void Reset()=>target=null;
    public (double X,double Y) Resolve(double x,double y,long now) {
        if(now-lastMove>100)Reset();
        return target??(x,y);
    }
    public (double X,double Y) Move(double x,double y,int dx,int dy,long now) {
        var start=Resolve(x,y,now);
        target=clamp(start.X+dx,start.Y+dy);lastMove=now;
        return target.Value;
    }
    public static (double X,double Y) Clamp(double x,double y,IReadOnlyList<Display> displays) {
        var result=(X:x,Y:y);double nearest=double.PositiveInfinity;
        foreach(var display in displays) {
            if(display.Width<1||display.Height<1)continue;
            double cx=Math.Clamp(x,display.X,display.X+display.Width-1);
            double cy=Math.Clamp(y,display.Y,display.Y+display.Height-1);
            double distance=(x-cx)*(x-cx)+(y-cy)*(y-cy);
            if(distance<nearest){nearest=distance;result=(cx,cy);}
        }
        return result;
    }
}
