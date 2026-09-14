import Foundation
import SwiftUI
import Testing

struct ViewRaster {
  let width: Int
  let height: Int
  let pixels: Data
  let png: Data

  func matches(_ other: ViewRaster) -> Bool {
    // Repeated native renders differed by one 8-bit level at one antialiased
    // edge pixel. Preserve exact dimensions and allow only that quantization.
    let equal =
      width == other.width && height == other.height
      && zip(pixels, other.pixels).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
    if !equal {
      let changes = zip(pixels, other.pixels).enumerated().filter { $0.element.0 != $0.element.1 }
      let maximum = changes.map { abs(Int($0.element.0) - Int($0.element.1)) }.max() ?? 0
      print(
        "Raster mismatch: \(width)x\(height) / \(other.width)x\(other.height); \(changes.count) channels; maximum delta \(maximum); first \(Array(changes.prefix(12)))"
      )
      let directory = URL(fileURLWithPath: "_build/validation", isDirectory: true)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? png.write(to: directory.appendingPathComponent("render-actual.png"))
      try? other.png.write(to: directory.appendingPathComponent("render-expected.png"))
    }
    return equal
  }

  func write(to url: URL) throws { try png.write(to: url) }
}

@MainActor func raster(
  _ content: some View, _ direction: LayoutDirection = .leftToRight, background: Color = .white
) throws -> ViewRaster {
  let renderer = ImageRenderer(
    content: content.padding(8).background(background)
      .environment(\.layoutDirection, direction))
  renderer.scale = 1
  let image = try #require(renderer.cgImage)
  let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
  let context = try #require(
    CGContext(
      data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let pixels = Data(bytes: try #require(context.data), count: image.width * image.height * 4)
  let png = try #require(
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
  return ViewRaster(width: image.width, height: image.height, pixels: pixels, png: png)
}
