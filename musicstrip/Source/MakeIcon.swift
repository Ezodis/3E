import AppKit
import Foundation
let output=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let n=base*scale, w=CGFloat(n)
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:n,pixelsHigh:n,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        NSColor(calibratedWhite:0.06,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:w*0.07,y:w*0.07,width:w*0.86,height:w*0.86),xRadius:w*0.19,yRadius:w*0.19).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:w*0.47,weight:.heavy),.foregroundColor:NSColor.white]
        let text="3£" as NSString, size=text.size(withAttributes:attrs)
        text.draw(at:NSPoint(x:(w-size.width)/2,y:(w-size.height)/2+w*0.015),withAttributes:attrs)
        NSGraphicsContext.restoreGraphicsState()
        let filename="icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output).appendingPathComponent(filename))
    }
}
