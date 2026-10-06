import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let outer = NSBezierPath(roundedRect:NSRect(x:38,y:38,width:948,height:948),xRadius:210,yRadius:210)
NSGradient(starting:NSColor(calibratedRed:0.1,green:0.15,blue:0.24,alpha:1),ending:NSColor(calibratedRed:0.025,green:0.045,blue:0.09,alpha:1))!.draw(in:outer,angle:-50)
let cyan = NSColor(calibratedRed:0.22,green:0.93,blue:0.79,alpha:1)
let orange = NSColor(calibratedRed:1,green:0.67,blue:0.32,alpha:1)
for y in stride(from:280,through:760,by:80) {
    NSColor.white.withAlphaComponent(0.09).setStroke()
    let p=NSBezierPath(); p.move(to:NSPoint(x:170,y:y)); p.line(to:NSPoint(x:854,y:y)); p.lineWidth=3; p.stroke()
}
let axis=NSBezierPath(); axis.move(to:NSPoint(x:512,y:250)); axis.line(to:NSPoint(x:512,y:820)); axis.lineWidth=4; axis.setLineDash([12,14],count:2,phase:0); NSColor.white.withAlphaComponent(0.35).setStroke(); axis.stroke()
for (i,y) in [620,460,700].enumerated() {
    orange.setFill(); NSBezierPath(roundedRect:NSRect(x:195+i*85,y:y,width:72,height:42),xRadius:16,yRadius:16).fill()
    cyan.setFill(); NSBezierPath(roundedRect:NSRect(x:757-i*85,y:1000-y,width:72,height:42),xRadius:16,yRadius:16).fill()
}
let arrow=NSBezierPath(); arrow.move(to:NSPoint(x:350,y:215)); arrow.line(to:NSPoint(x:674,y:215)); arrow.move(to:NSPoint(x:350,y:215)); arrow.line(to:NSPoint(x:400,y:260)); arrow.move(to:NSPoint(x:350,y:215)); arrow.line(to:NSPoint(x:400,y:170)); arrow.move(to:NSPoint(x:674,y:215)); arrow.line(to:NSPoint(x:624,y:260)); arrow.move(to:NSPoint(x:674,y:215)); arrow.line(to:NSPoint(x:624,y:170)); arrow.lineWidth=19; arrow.lineCapStyle = .round; cyan.setStroke(); arrow.stroke()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
