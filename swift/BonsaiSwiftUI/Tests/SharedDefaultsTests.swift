import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

private func defaultsEnvironment(
  symbol: Double? = nil, spacing: Double? = nil, primary: UInt32? = nil,
  secondary: UInt32? = nil, foreground: UInt8? = nil, control: UInt8 = 5,
  bodySize: Double? = nil
) throws -> ViewEnvironment {
  var tokens = WireWriter()
  for value in [symbol, spacing] + [Double?](repeating: nil, count: 12) {
    tokens.integer(UInt8(value == nil ? 0 : 1))
    if let value { tokens.integer(value.bitPattern) }
  }
  for value in [primary, secondary] + [UInt32?](repeating: nil, count: 7) {
    tokens.integer(UInt8(value == nil ? 0 : 1))
    if let value { tokens.integer(value) }
  }
  for role in 0..<8 {
    let size = role == 0 ? bodySize : nil
    tokens.integer(UInt8(size == nil ? 0 : 1))
    if let size { tokens.integer(size.bitPattern) }
    tokens.integer(UInt8(0))
  }
  tokens.integer(UInt8(foreground == nil ? 0 : 1))
  if let foreground { tokens.integer(foreground) }
  tokens.bytes.append(Data(repeating: 0, count: 56))
  var writer = WireWriter()
  writer.bytes.append(contentsOf: [0, 0, 0, control])
  writer.integer(UInt16(tokens.bytes.count))
  writer.bytes.append(tokens.bytes)
  var reader = WireReader(writer.bytes)
  let environment = try ViewEnvironment.decode(&reader)
  #expect(reader.remaining == 0)
  return environment
}

@MainActor struct SharedDefaultsTests {
  @Test func omittedActionSymbolsUseRecommendedSizeAndExplicitSizeWins() throws {
    for name in ["magnifyingglass", "xmark", "ellipsis", "star"] {
      for size: Double? in [nil, 27] {
        let actual = NativeSymbolView(
          symbol: RenderSymbol(name: name, size: size, color: nil, rendering: 0)
        )
        .font(.system(size: 35)).foregroundStyle(Color.blue)
        let expected = Image(systemName: name).symbolRenderingMode(.monochrome)
          .font(.system(size: size ?? 19)).foregroundStyle(Color.blue)
        #expect(try raster(actual).matches(raster(expected)))
      }
    }
  }

  @Test func nestedOverridesMergeAndExplicitPropertiesWin() throws {
    let outer = try defaultsEnvironment(symbol: 29, primary: 0xffff_0000)
    let inner = try defaultsEnvironment(spacing: 0)
    let symbol = NativeSymbolView(
      symbol: RenderSymbol(name: "star", size: nil, color: nil, rendering: 0))
    let nested = symbol.modifier(SwiftUIEnvironmentModifier(values: inner))
      .modifier(SwiftUIEnvironmentModifier(values: outer))
    let expected = Image(systemName: "star").symbolRenderingMode(.monochrome)
      .font(.system(size: 29)).foregroundStyle(Color(argb: 0xffff_0000))
    #expect(try raster(nested).matches(raster(expected)))
    let explicit = NativeSymbolView(
      symbol: RenderSymbol(name: "star", size: 23, color: 0xff00_00ff, rendering: 0)
    )
    .modifier(SwiftUIEnvironmentModifier(values: outer))
    #expect(
      try raster(explicit).matches(
        raster(
          Image(systemName: "star").symbolRenderingMode(.monochrome)
            .font(.system(size: 23)).foregroundStyle(Color(argb: 0xff00_00ff)))))
    let secondary = try defaultsEnvironment(secondary: 0xff00_ff00, foreground: 1)
    #expect(
      try raster(symbol.modifier(SwiftUIEnvironmentModifier(values: secondary)))
        .matches(
          raster(
            Image(systemName: "star").symbolRenderingMode(.monochrome)
              .font(.system(size: 19)).foregroundStyle(Color(argb: 0xff00_ff00)))))
  }

  @Test func columnSpacingUsesThemeAndPreservesZero() throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.create(1), TreeFixture.text(2, "One"), TreeFixture.text(3, "Two"),
          TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
        ])
      ).tree)
    let root = try #require(tree.root)
    for spacing: Double? in [nil, 0, 24] {
      let environment = try defaultsEnvironment(spacing: spacing)
      let actual = NativeNodeView(node: root, activate: { _ in })
        .modifier(SwiftUIEnvironmentModifier(values: environment))
      let expected = VStack(spacing: spacing ?? 16) {
        NativeTextView(text: "One")
        NativeTextView(text: "Two")
      }.modifier(SwiftUIEnvironmentModifier(values: environment))
      #expect(try raster(actual).matches(raster(expected)))
    }
  }

  @Test func themeChangesRetainInputControllerAndNodeIdentity() throws {
    let tree = RenderTree()
    let initial = try NodeStore().staging(TreeFixture.initial).tree
    tree.commit(initial)
    let root = try #require(tree.root)
    let button = try #require(tree.nodes[3])
    let focus = try #require(button.focusController)
    for size in [19.0, 31.0, 19.0] {
      let theme = try defaultsEnvironment(symbol: size)
      _ = try raster(
        NativeNodeView(node: root, activate: { _ in })
          .modifier(SwiftUIEnvironmentModifier(values: theme)))
      #expect(tree.root === root)
      #expect(tree.nodes[3] === button)
      #expect(button.focusController === focus)
    }
  }

  @Test func invalidOverridesAreRejected() throws {
    for invalid in [0.0, -1, .infinity, .nan] {
      #expect(throws: (any Error).self) { try defaultsEnvironment(symbol: invalid) }
      #expect(throws: (any Error).self) { try defaultsEnvironment(bodySize: invalid) }
    }
    for invalid in [-1.0, .infinity, .nan] {
      #expect(throws: (any Error).self) { try defaultsEnvironment(spacing: invalid) }
    }
    #expect(throws: (any Error).self) { try defaultsEnvironment(foreground: 9) }
    #expect(throws: (any Error).self) { try defaultsEnvironment(control: 6) }
  }

  @Test func macOSKeepsNativeCompactControls() throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.button(1, role: 0, style: 1), TreeFixture.text(2, "Go"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ])
      ).tree)
    let root = try #require(tree.root)
    let actual = NativeNodeView(node: root, activate: { _ in }).controlSize(.mini)
    let expected = Button(action: {}) { NativeTextView(text: "Go") }
      .buttonStyle(.plain).controlSize(.mini)
    #expect(try raster(actual).matches(raster(expected)))
  }
}

private func roleText(_ role: UInt8, size: Double? = nil, italic: Bool = false) throws -> RenderText
{
  var writer = WireWriter()
  let title = "Readable title"
  writer.integer(UInt32(title.utf8.count))
  writer.bytes.append(contentsOf: title.utf8)
  writer.integer(UInt8(1))
  writer.integer(UInt8(size == nil ? 0 : 1))
  if let size { writer.integer(size.bitPattern) }
  writer.bytes.append(contentsOf: [0, 0, 0, role, 0, italic ? 1 : 0, 0, 0, 0])
  var reader = WireReader(writer.bytes)
  return try reader.text()
}

extension SharedDefaultsTests {
  @Test func textRolesScaleAndRespectExplicitSizeAndTheme() throws {
    let theme = try defaultsEnvironment(bodySize: 21)
    let body = try roleText(0)
    #expect(
      try raster(
        NativeTextView(text: body)
          .modifier(SwiftUIEnvironmentModifier(values: theme))
      )
      .matches(raster(Text("Readable title").font(.system(size: 21)))))
    let title = try roleText(1, size: 30)
    #expect(
      try raster(NativeTextView(text: title))
        .matches(raster(Text("Readable title").font(.system(size: 30, weight: .bold)))))
    let hint = try roleText(6, italic: true)
    let small = try raster(NativeTextView(text: hint).environment(\.dynamicTypeSize, .small))
    let large = try raster(
      NativeTextView(text: hint).environment(\.dynamicTypeSize, .accessibility3))
    #if os(iOS)
      #expect(large.height > small.height)
    #else
      // macOS does not scale ScaledMetric with the iOS Dynamic Type category.
      #expect(large.height == small.height)
      let scaled = Text("Readable title").font(
        NativeTextFont.resolve(
          size: 13, weight: 0, italic: true, family: nil, inherited: nil, scale: 2))
      #expect(try raster(scaled).height > small.height)
    #endif
    #expect(throws: (any Error).self) { try roleText(9) }
  }

  @Test func semanticForegroundRespondsToAppearance() throws {
    let theme = try defaultsEnvironment(foreground: 1)
    let symbol = NativeSymbolView(
      symbol: RenderSymbol(name: "star", size: nil, color: nil, rendering: 0)
    )
    .modifier(SwiftUIEnvironmentModifier(values: theme))
    let light = try raster(symbol.environment(\.colorScheme, .light), background: .clear)
    let dark = try raster(symbol.environment(\.colorScheme, .dark), background: .clear)
    #expect(light.pixels != dark.pixels)
  }

  @Test func recipeUsesSharedPaintAndReducedTransparencyKeepsChildOpaque() throws {
    initializeAccessibilityApplication()
    var payload = WireWriter()
    payload.bytes.append(contentsOf: [0, 1, 0, 5])  // Translucent sheet recipe, no presentation changes.
    for value in [0.0, 0, 0, 0, 0, 1] { payload.integer(value.bitPattern) }
    for _ in 0..<3 { payload.integer(UInt32(0)) }
    payload.integer(UInt16(0))  // All recipe properties omitted.
    let registry = BonsaiNativeViews().includingStandardViews()
    let prepared = try registry.prepare(
      RenderNativeView(kind: 8, version: 3, capabilities: [], payload: payload.bytes))
    try prepared.definition.validateChildren(prepared.properties, 1)
    let create = TreeFixture.operation(OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(NodeKindId.nativeWidget))
      $0.integer(UInt32(8))
      $0.integer(UInt16(3))
      $0.integer(UInt64(0))
      $0.integer(UInt32(payload.bytes.count))
      $0.bytes.append(payload.bytes)
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.nativeEvent))
      $0.integer(UInt64(9))
    }
    let tree = RenderTree()
    let store = try NodeStore().staging(
      TreeFixture.frame([
        create, TreeFixture.text(2, "Visible child"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    try tree.validate(store)
    tree.commit(store)
    let root = try #require(tree.root)
    let view = NativeNodeView(node: root, activate: { _ in }).padding(30)
    let properties = try #require(prepared.properties as? RenderSurface)
    var centerColors: [NSColor] = []
    for backdrop in [Color.red, Color.blue] {
      let image = try #require(
        ImageRenderer(
          content:
            NativeSurfacePaint(properties: properties, reduceTransparency: true)
            .frame(width: 100, height: 100).background(backdrop)
        ).cgImage)
      centerColors.append(try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 50, y: 50)))
    }
    #expect(centerColors[0] == centerColors[1])
    let host = NSHostingView(rootView: view)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 0)
  }
}

extension SharedDefaultsTests {
  @Test func liveThemeUpdatePreservesFocusedFieldDraftSelectionAndComposition() async throws {
    initializeAccessibilityApplication()
    let snapshot = try TextSnapshot(
      sessionID: 91, documentRevision: 1, acceptedLocalRevision: 0,
      mode: .forceReplace,
      value: TextValue(text: "Draft", selection: NSRange(location: 5, length: 0)))
    let controller = NativeTextFieldController(
      snapshot: snapshot, secure: false,
      configuration: try TextEditorConfiguration(submitOnReturn: true), label: "Draft", prompt: "",
      emit: { _ in true }, failed: { Issue.record($0) })
    let multiline = NativeTextController(
      snapshot: snapshot,
      configuration: try TextEditorConfiguration(), emit: { _ in true },
      failed: { Issue.record($0) })
    func content(_ theme: ViewEnvironment) -> some View {
      VStack {
        NativeTextFieldView(controller: controller).frame(width: 300, height: 40)
        NativeTextEditorView(controller: multiline).frame(width: 300, height: 80)
      }.modifier(SwiftUIEnvironmentModifier(values: theme))
    }
    let host = NSHostingView(rootView: content(try defaultsEnvironment()))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 340, height: 160),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      multiline.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let field = controller.field
    field.selectText(nil)
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.insertText("Local draft", replacementRange: NSRange(location: 0, length: 5))
    editor.setMarkedText(
      "中文", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 5, length: 0))
    try await settleAccessibility(host)
    let draft = editor.string
    let selected = editor.selectedRange()
    let marked = editor.markedRange()
    var theme = try defaultsEnvironment(symbol: 25, primary: 0xff00_55aa, bodySize: 21)
    theme.mode = 2
    theme.tint = 0xffff_0000
    theme.fontFamily = "Menlo"
    host.rootView = content(theme)
    try await settleAccessibility(host)
    #expect(controller.field === field)
    #expect(field.font?.pointSize == 21)
    #expect(multiline.view.font?.pointSize == 21)
    #expect(multiline.view.string == "Draft")
    #expect(field.currentEditor() === editor)
    #expect(window.firstResponder === editor)
    #expect(editor.string == draft)
    #expect(editor.selectedRange() == selected)
    #expect(editor.markedRange() == marked)
  }
}

private func scopedThemePayload(
  symbolRendering: UInt8? = nil, textRole: UInt8? = nil,
  hintForeground: UInt8? = nil, hintItalic: Bool? = nil,
  sheetOpacity: Double? = nil, actionMaterial: UInt8? = nil,
  actionCapsule: Bool? = nil, actionBackground: UInt8? = nil,
  shadowAlpha: Double? = nil, materialAlpha: Double? = nil, sheetTintAlpha: Double? = nil
) throws -> ViewEnvironment {
  var data = WireWriter()
  data.bytes.append(Data(repeating: 0, count: 40))
  func byte(_ value: UInt8?) {
    data.integer(UInt8(value == nil ? 0 : 1))
    if let value { data.integer(value) }
  }
  func number(_ value: Double?) {
    data.integer(UInt8(value == nil ? 0 : 1))
    if let value { data.integer(value.bitPattern) }
  }
  for value in [nil, shadowAlpha, materialAlpha] { number(value) }
  byte(symbolRendering)
  byte(textRole)
  for role in 0..<8 {
    byte(role == 6 ? hintForeground : nil)
    byte(role == 6 ? hintItalic.map { $0 ? 1 : 0 } : nil)
  }
  for recipe in 0..<7 {
    byte(recipe == 2 ? actionMaterial : nil)
    byte(recipe == 2 ? actionCapsule.map { $0 ? 1 : 0 } : nil)
    byte(recipe == 2 ? actionBackground : nil)
    number(recipe == 5 ? sheetOpacity : nil)
    number(recipe == 5 ? sheetTintAlpha : nil)
  }
  var wire = WireWriter()
  wire.bytes.append(contentsOf: [0, 0, 0, 5])
  wire.integer(UInt16(data.bytes.count))
  wire.bytes.append(data.bytes)
  var reader = WireReader(wire.bytes)
  return try ViewEnvironment.decode(&reader)
}

extension SharedDefaultsTests {
  @Test func themeOwnsOmittedSymbolRenderingAndExplicitRenderingWins() throws {
    let outer = try scopedThemePayload(symbolRendering: 1)
    let inner = try scopedThemePayload(textRole: 6)
    for rendering in [3, 0] {
      let actual = NativeSymbolView(
        symbol: RenderSymbol(
          name: "person.crop.circle.fill", size: nil, color: nil, rendering: rendering)
      )
      .modifier(SwiftUIEnvironmentModifier(values: inner))
      .modifier(SwiftUIEnvironmentModifier(values: outer))
      let expected = Image(systemName: "person.crop.circle.fill")
        .symbolRenderingMode(rendering == 3 ? .hierarchical : .monochrome)
        .font(.system(size: 19)).foregroundStyle(Color.primary)
      #expect(try raster(actual).matches(raster(expected)))
    }
  }

  @Test func themeOwnsRoleForegroundAndItalicWithoutFreezingOmission() throws {
    let theme = try scopedThemePayload(textRole: 6, hintForeground: 0, hintItalic: true)
    let actual = NativeTextView(text: RenderText("Theme hint"))
      .modifier(SwiftUIEnvironmentModifier(values: theme))
    let expected = Text("Theme hint").font(.system(size: 13).weight(.regular).italic())
      .foregroundStyle(Color.primary)
    #expect(try raster(actual).matches(raster(expected)))
  }

  @Test func themeOwnsSurfacePaintAndPerFieldInheritance() throws {
    let outer = try scopedThemePayload(
      sheetOpacity: 0.75, actionMaterial: 2,
      actionCapsule: false, actionBackground: 3, shadowAlpha: 0.3, materialAlpha: 0.25,
      sheetTintAlpha: 0.5)
    let inner = try scopedThemePayload(textRole: 6)
    let merged = inner.defaults.inheriting(outer.defaults)
    var sheet = RenderSurface(
      mode: 0, presentationBackground: false, colors: [0], radius: 0,
      shadowRadius: 0, shadowX: 0, shadowY: 0, borderWidth: 0, opacity: 1,
      shadowColor: 0, borderColor: 0, recipe: 5, overrideMask: 0)
    #expect(sheet.resolved(merged, scheme: .light, contrast: .standard).opacity == 0.75)
    #expect((sheet.resolved(merged, scheme: .light, contrast: .standard).colors[0] >> 24) == 128)
    sheet.overrideMask = 1 << 5
    #expect(sheet.resolved(merged, scheme: .light, contrast: .standard).opacity == 1)
    sheet.recipe = 2
    sheet.overrideMask = 0
    let action = sheet.resolved(merged, scheme: .light, contrast: .standard)
    #expect(action.mode == 4)
    #expect(!action.capsule)
    #expect(action.colors == [merged.argb(3, scheme: .light, contrast: .standard)])
    #expect((merged.argb(8, scheme: .light, contrast: .standard) >> 24) == 64)
  }

  @Test func invalidThemeChoicesAndOpacitiesAreRejected() throws {
    for value in [-0.1, 1.1, Double.nan, Double.infinity] {
      #expect(throws: (any Error).self) { try scopedThemePayload(sheetOpacity: value) }
      #expect(throws: (any Error).self) { try scopedThemePayload(shadowAlpha: value) }
      #expect(throws: (any Error).self) { try scopedThemePayload(sheetTintAlpha: value) }
    }
    #expect(throws: (any Error).self) { try scopedThemePayload(symbolRendering: 3) }
    #expect(throws: (any Error).self) { try scopedThemePayload(textRole: 8) }
    #expect(throws: (any Error).self) { try scopedThemePayload(actionMaterial: 4) }
    #expect(throws: (any Error).self) { try scopedThemePayload(hintForeground: 9) }
  }
}

extension SharedDefaultsTests {
  @Test func richTextUsesTheSameScopedTypographyAsPlainText() throws {
    let theme = try defaultsEnvironment(bodySize: 23)
    let spans = [
      RenderTextSpan(
        value: "Theme body", fontSize: nil, weight: nil, color: nil,
        italic: false, underline: false, strikethrough: false)
    ]
    let rich = NativeRichTextView(spans: spans).modifier(SwiftUIEnvironmentModifier(values: theme))
    let plain = NativeTextView(text: RenderText("Theme body")).modifier(
      SwiftUIEnvironmentModifier(values: theme))
    #expect(try raster(rich).matches(raster(plain)))
  }
}
