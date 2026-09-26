import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/dmg/background.png"
let scale: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2])!) : 1
let width: CGFloat = 660, height: CGFloat = 420
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(660 * scale), pixelsHigh: Int(420 * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width * scale, height: height * scale)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let background = NSGradient(starting: color(0.90, 0.95, 0.98), ending: color(0.98, 0.99, 1))!
background.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 20)
// Quiet radar arcs echo the app identity without competing with draggable icons.
for radius: CGFloat in [150, 210, 270] {
    let circle = NSBezierPath(ovalIn: NSRect(x: 640-radius, y: 385-radius, width: radius*2, height: radius*2))
    color(0.25, 0.7, 0.9, 0.07).setStroke(); circle.lineWidth = 1; circle.stroke()
}
func text(_ string: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink]
    (string as NSString).draw(at: NSPoint(x: x, y: height-top-size*1.25), withAttributes: attributes)
}
text("Install iPScanner", x: 38, top: 30, size: 30, weight: .semibold, ink: color(0.06,0.17,0.28))
text("Drag iPScanner to the Applications folder.", x: 39, top: 78, size: 15, weight: .regular, ink: color(0.28,0.40,0.50))
for x: CGFloat in [175, 485] {
    let plate = NSBezierPath(roundedRect: NSRect(x:x-66,y:height-205-65,width:132,height:130),xRadius:26,yRadius:26)
    color(0.5,0.75,0.95,0.055).setFill();plate.fill()
    color(0.5,0.75,0.95,0.13).setStroke();plate.lineWidth=1;plate.stroke()
}
let arrow = NSBezierPath();arrow.move(to:NSPoint(x:285,y:height-205));arrow.line(to:NSPoint(x:375,y:height-205))
arrow.move(to:NSPoint(x:363,y:height-193));arrow.line(to:NSPoint(x:375,y:height-205));arrow.line(to:NSPoint(x:363,y:height-217))
arrow.lineWidth=3;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;color(0.1,0.5,0.8).setStroke();arrow.stroke()
let line=NSBezierPath();line.move(to:NSPoint(x:38,y:84));line.line(to:NSPoint(x:622,y:84));line.lineWidth=1;color(0.5,0.7,0.85,0.18).setStroke();line.stroke()
text("Open iPScanner from Applications to get started.",x:39,top:352,size:14,weight:.medium,ink:color(0.17,0.29,0.39))
text("After copying, you can eject this disk image.",x:39,top:378,size:12,weight:.regular,ink:color(0.36,0.46,0.54))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
