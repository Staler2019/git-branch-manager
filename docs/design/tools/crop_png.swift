// Crops a rectangular region out of a PNG, in pixel coordinates with a
// top-left origin (matching the coordinates a human would read off a
// screenshot viewer). Paired with render_pdf.swift to pull individual UI
// regions -- toolbar, sidebar, a commit row, the expansion card -- out of a
// full-page design render for side-by-side comparison against an
// implementation screenshot.
//
// Usage: swift crop_png.swift <in.png> <out.png> <x> <y> <w> <h>
import Foundation
import AppKit

let a = CommandLine.arguments
guard a.count == 7, let src = NSImage(contentsOfFile: a[1]),
      let tiff = src.tiffRepresentation, let rep0 = NSBitmapImageRep(data: tiff) else {
    print("usage: crop_png.swift <in.png> <out.png> <x> <y> <w> <h>")
    exit(1)
}
let x = Int(a[3])!, y = Int(a[4])!, w = Int(a[5])!, h = Int(a[6])!
guard let cg = rep0.cgImage, let cropped = cg.cropping(to: CGRect(x: x, y: y, width: w, height: h))
else {
    print("crop rect out of bounds")
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cropped)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: a[2]))
print("cropped \(w)x\(h) -> \(a[2])")
