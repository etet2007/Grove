import AppKit
import Foundation
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:800,pixelsHigh:580,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
func fill(_ r:NSRect,_ c:NSColor){c.setFill();r.fill()}
func label(_ t:String,_ x:CGFloat,_ y:CGFloat,_ s:CGFloat = 14){(t as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:s),.foregroundColor:NSColor.gray])}
fill(NSRect(x:0,y:0,width:800,height:580),NSColor(white:0.96,alpha:1))
label("MyGit / Green grove",24,544,24)
label("Concept crops · raster artwork · surrounding tests only",24,518,13)
for (i,name) in ["A-vector-green","B-glass-sculpted-green"].enumerated(){
 let x=CGFloat(i*400)
 let source=NSImage(contentsOf:dir.appendingPathComponent(name+".png"))!
 let sz=source.size
 let crop=NSRect(x:sz.width*0.112,y:sz.height*0.112,width:sz.width*0.776,height:sz.height*0.776)
 func draw(_ r:NSRect){source.draw(in:r,from:crop,operation:.sourceOver,fraction:1)}
 label(i==0 ? "A / Vector-like" : "B / Sculpted glass",x+24,478,18)
 draw(NSRect(x:x+85,y:252,width:230,height:230))
 for (row,dark) in [true,false].enumerated(){
  let y=CGFloat(132-row*106)
  fill(NSRect(x:x+20,y:y,width:360,height:98),NSColor(white:dark ? 0.13:0.88,alpha:1))
  for (j,s) in [16,32,64].enumerated(){
   let cx=x+CGFloat(78+j*120)
   draw(NSRect(x:cx-CGFloat(s)/2,y:y+24,width:CGFloat(s),height:CGFloat(s)))
   label("\(s) px",cx-17,y+5,10)
  }
 }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("comparison.png"))
