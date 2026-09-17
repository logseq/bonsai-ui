import SwiftUI

private struct NativeLabelIconKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var bonsaiLabelIcon: Bool {
    get { self[NativeLabelIconKey.self] }
    set { self[NativeLabelIconKey.self] = newValue }
  }
}

struct RenderSymbol: Equatable, Sendable {
  let name: String
  let size: Double?
  let color: UInt32?
  let rendering: Int

  static func decode(_ reader: inout WireReader) throws -> RenderSymbol {
    let name = try reader.string()
    guard !name.isEmpty,
      name.utf8.allSatisfy({ byte in
        (65...90).contains(byte) || (97...122).contains(byte)
          || (48...57).contains(byte) || byte == 46 || byte == 95
      })
    else { throw TreeError.invalidProperties }
    let size = try reader.positiveOptionalDouble()
    let color = try reader.flag() ? reader.integer(UInt32.self) : nil
    let rendering = try reader.choice(3)
    #if os(macOS)
      let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    #else
      let available = UIImage(systemName: name) != nil
    #endif
    guard available else { throw TreeError.unavailableSymbol(name) }
    return RenderSymbol(name: name, size: size, color: color, rendering: rendering)
  }
}

struct NativeSymbolView: View {
  let symbol: RenderSymbol
  @Environment(\.bonsaiDefaults) private var defaults
  @Environment(\.bonsaiLabelIcon) private var isLabelIcon

  private var mode: SymbolRenderingMode {
    switch symbol.rendering == 3 ? defaults.defaultSymbolRendering() : symbol.rendering {
    case 1: .hierarchical
    case 2: .multicolor
    default: .monochrome
    }
  }

  @ViewBuilder private var image: some View {
    let image = Image(systemName: symbol.name).symbolRenderingMode(mode)
    image.font(.system(size: symbol.size ?? defaults.metric(0)))
  }

  @ViewBuilder var body: some View {
    Group {
      if let color = symbol.color {
        image.foregroundStyle(Color(argb: color))
      } else {
        image
      }
    }.accessibilityHidden(!isLabelIcon)
  }
}
