// Renders every page of a PDF to PNG at a fixed scale, using PDFKit (macOS
// only). Used to turn Design.pdf-style layout references into pixel data for
// side-by-side comparison against `GBM_SCREENSHOT` captures -- see the
// "Verification" section of the UI redesign plan.
//
// Usage: swift render_pdf.swift <input.pdf> <output-dir> [scale]
//
// Writes <output-dir>/page-01.png, page-02.png, ... at `scale`x (default 4x,
// which is enough resolution to crop small regions like a toolbar or a
// single commit row without visible upscaling artifacts).
import Foundation
import PDFKit
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    print("usage: render_pdf.swift <pdf> <outdir> [scale]")
    exit(1)
}
let outDir = args[2]
let scale: CGFloat = args.count >= 4 ? CGFloat(Double(args[3]) ?? 4.0) : 4.0
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
print("pages: \(doc.pageCount)")

for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i) else { continue }
    let rect = page.bounds(for: .mediaBox)
    let size = NSSize(width: rect.width * scale, height: rect.height * scale)
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -rect.origin.x, y: -rect.origin.y)
    page.draw(with: .mediaBox, to: ctx)
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let path = "\(outDir)/page-\(String(format: "%02d", i + 1)).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(Int(size.width))x\(Int(size.height))")
}
