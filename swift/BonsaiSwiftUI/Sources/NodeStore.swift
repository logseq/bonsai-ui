import Foundation

enum TreeError: Error, Equatable {
  case revisionMismatch
  case invalidIdentity
  case duplicateNode
  case missingNode
  case invalidProperties
  case invalidBindings
  case invalidChildren
  case invalidGraph
  case unsupportedNode(Int)
  case unavailableSymbol(String)
}

struct RenderNode: Equatable, Sendable {
  let id: UInt64
  let kind: Int
  var properties: NodeProperties
  var bindings: [Int: UInt64]
  var children: [UInt64] = []
}

enum NodeProperties: Equatable, Sendable {
  case nativeView(RenderNativeView)
  case empty
  case gesture
  case focusScope(autofocus: Bool)
  case keyboardListener(RenderKeyboardListener)
  case hoverRegion(blocksBehind: Bool)
  case label
  case badge(RenderBadge)
  case sheet(RenderSheet)
  case popover(RenderPopover)
  case removal(RenderRemoval)
  case refresh(RenderRefresh)
  case scrollSections(RenderScrollSections)
  case scrollSection(RenderScrollSection)
  case toolbar(RenderToolbar)
  case help(String)
  case groupBox(hasLabel: Bool)
  case slider(RenderSlider)
  case booleanControl(RenderBooleanControl)
  case civilPicker(RenderCivilPicker)
  case scrollTargets(RenderScrollTargets)
  case table(RenderTable)
  case menu(RenderMenu)
  case picker(RenderPicker)
  case swipeActions(RenderSwipeActions)
  case swipeAction(RenderSwipeAction)
  case morphingSurface(RenderMorphingSurface)
  case tabs(RenderTabKey)
  case tab(RenderTab)
  case navigationSplit(RenderNavigationSplit)
  case navigationStack(title: String)
  case navigationDestination(RenderNavigationDestination)
  case ignoresSafeArea(RenderSafeArea)
  case safeAreaPadding(leading: Double, top: Double, trailing: Double, bottom: Double)
  case progress(RenderProgress)
  case controlSize(Int)
  case semantics(RenderSemantics)
  case scroll(
    vertical: Bool, indicators: Bool, fillViewport: Bool, initialAnchor: InitialScrollAnchor)
  case divider
  case flow(RenderFlow)
  case row(spacing: Double?, alignment: Int)
  case column(spacing: Double?, alignment: Int)
  case stack(alignment: Int)
  case overlay(alignment: Int)
  case weighted(RenderWeightedStack, vertical: Bool)
  case layoutPriority(Double)
  case offset(x: Double, y: Double)
  case text(RenderText)
  case richText([RenderTextSpan])
  case button(enabled: Bool, role: Int, style: Int, autofocus: Bool)
  case environment(ViewEnvironment)
  case symbol(RenderSymbol)
  case image(RenderImage)
  case textEditor(RenderTextEditor)
  case textField(RenderTextField)
  case collection(RenderCollectionCatalog)
  case collectionWindow(RenderCollectionWindow)
  case frame(RenderFrame)
  case spacer(minLength: Double?)
  case padding(leading: Double, top: Double, trailing: Double, bottom: Double)
  case background(color: UInt32, cornerRadius: Double)
  case clip(cornerRadius: Double, antialiased: Bool)
  case animatedOpacity(RenderAnimatedOpacity)
  case opacity(Double)
  case projection(RenderProjection)
}

extension NodeProperties {
  var presentation: RenderPresentation? {
    switch self {
    case .popover(let value): .popover(value)
    case .sheet(let value): .sheet(value)
    default: nil
    }
  }

  var textEditing: RenderTextEditor? {
    switch self {
    case .textEditor(let editor): return editor
    case .textField(let field): return field.editing
    default: return nil
    }
  }
}

struct RenderText: Equatable, Sendable, ExpressibleByStringLiteral {
  let value: String
  var style: RenderTextStyle?
  var alignment = 0
  var lineLimit: Int?
  var truncation = 0

  init(stringLiteral value: String) { self.value = value }
  init(_ value: String) { self.value = value }
}

struct RenderTextStyle: Equatable, Sendable {
  let fontSize: Double?
  let weight: Int?
  let lineSpacing: Double?
  let argb: UInt32?
}

extension WireReader {
  mutating func identity() throws -> UInt64 {
    let value = try integer(UInt64.self)
    guard value > 0, value <= UInt64(Int64.max) else { throw TreeError.invalidIdentity }
    return value
  }

  mutating func flag() throws -> Bool {
    let value = try integer(UInt8.self)
    guard value <= 1 else { throw TreeError.invalidProperties }
    return value == 1
  }

  mutating func choice(_ upperBound: Int) throws -> Int {
    let value = Int(try integer(UInt8.self))
    guard value <= upperBound else { throw TreeError.invalidProperties }
    return value
  }

  mutating func finiteDouble() throws -> Double {
    let value = Double(bitPattern: try integer(UInt64.self))
    guard value.isFinite else { throw TreeError.invalidProperties }
    return value
  }

  mutating func positiveOptionalDouble() throws -> Double? {
    guard try flag() else { return nil }
    let value = try finiteDouble()
    guard value > 0 else { throw TreeError.invalidProperties }
    return value
  }

  mutating func nonnegativeDouble() throws -> Double {
    let value = try finiteDouble()
    guard value >= 0 else { throw TreeError.invalidProperties }
    return value
  }

  mutating func nonnegativeOptionalDouble() throws -> Double? {
    guard try flag() else { return nil }
    let value = try finiteDouble()
    guard value >= 0 else { throw TreeError.invalidProperties }
    return value
  }

  mutating func string() throws -> String {
    let length = Int(try integer(UInt32.self))
    guard length <= ProtocolLimits.maxStringBytes else { throw WireError.limitExceeded }
    guard let value = String(data: try data(length), encoding: .utf8)
    else { throw TreeError.invalidProperties }
    return value
  }

  mutating func text() throws -> RenderText {
    var text = RenderText(try string())
    if try flag() {
      let size = try positiveOptionalDouble()
      let weight = try flag() ? choice(3) : nil
      let spacing = try nonnegativeOptionalDouble()
      let argb = try flag() ? integer(UInt32.self) : nil
      text.style = RenderTextStyle(fontSize: size, weight: weight, lineSpacing: spacing, argb: argb)
    }
    text.alignment = try choice(2)
    if try flag() {
      let lines = Int(try integer(UInt32.self))
      guard lines > 0 else { throw TreeError.invalidProperties }
      text.lineLimit = lines
    }
    text.truncation = try choice(2)
    return text
  }

  mutating func bindings() throws -> [Int: UInt64] {
    let count = Int(try integer(UInt16.self))
    var bindings: [Int: UInt64] = [:]
    for _ in 0..<count {
      let tag = Int(try integer(UInt16.self))
      let handler = try identity()
      guard bindings.updateValue(handler, forKey: tag) == nil
      else { throw TreeError.invalidBindings }
    }
    return bindings
  }
}

private func properties(_ reader: inout WireReader, kind: Int) throws -> NodeProperties {
  switch kind {
  case NodeKindId.nativeWidget: return .nativeView(try RenderNativeView.decode(&reader))
  case NodeKindId.gesture: return .gesture
  case NodeKindId.focusScope: return .focusScope(autofocus: try reader.flag())
  case NodeKindId.keyboardListener:
    return .keyboardListener(try RenderKeyboardListener.decode(&reader))
  case NodeKindId.hoverRegion: return .hoverRegion(blocksBehind: try reader.flag())
  case NodeKindId.slider, NodeKindId.rangeSlider:
    return .slider(try RenderSlider.decode(&reader, ranged: kind == NodeKindId.rangeSlider))
  case NodeKindId.badge: return .badge(try RenderBadge.decode(&reader))
  case NodeKindId.label: return .label
  case NodeKindId.sheet: return .sheet(try RenderSheet.decode(&reader))
  case NodeKindId.popover: return .popover(try RenderPopover.decode(&reader))
  case NodeKindId.removal: return .removal(try RenderRemoval.decode(&reader))
  case NodeKindId.refresh: return .refresh(try RenderRefresh.decode(&reader))
  case NodeKindId.scrollSections: return .scrollSections(try RenderScrollSections.decode(&reader))
  case NodeKindId.scrollSection: return .scrollSection(try RenderScrollSection.decode(&reader))
  case NodeKindId.toolbar: return .toolbar(try RenderToolbar.decode(&reader))
  case NodeKindId.help:
    let message = try reader.string()
    // Match OCaml String.trim without discarding other Unicode whitespace.
    guard !message.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000C}")).isEmpty
    else { throw TreeError.invalidProperties }
    return .help(message)
  case NodeKindId.groupBox: return .groupBox(hasLabel: try reader.flag())
  case NodeKindId.toggle: return .booleanControl(try RenderBooleanControl.decode(&reader))
  case NodeKindId.disclosureGroup:
    return .booleanControl(try RenderBooleanControl.decode(&reader, disclosure: true))
  case NodeKindId.datePicker: return .civilPicker(try RenderCivilPicker.decode(&reader, date: true))
  case NodeKindId.timePicker:
    return .civilPicker(try RenderCivilPicker.decode(&reader, date: false))
  case NodeKindId.scrollTargets: return .scrollTargets(try RenderScrollTargets.decode(&reader))
  case NodeKindId.table: return .table(try RenderTable.decode(&reader))
  case NodeKindId.menu: return .menu(try RenderMenu.decode(&reader))
  case NodeKindId.picker: return .picker(try RenderPicker.decode(&reader))
  case NodeKindId.swipeActions: return .swipeActions(try RenderSwipeActions.decode(&reader))
  case NodeKindId.swipeAction: return .swipeAction(try RenderSwipeAction.decode(&reader))
  case NodeKindId.morphingSurface:
    return .morphingSurface(try RenderMorphingSurface.decode(&reader))
  case NodeKindId.tabs: return .tabs(try RenderTabKey.decode(&reader))
  case NodeKindId.tab: return .tab(try RenderTab.decode(&reader))
  case NodeKindId.navigationSplit:
    return .navigationSplit(try RenderNavigationSplit.decode(&reader))
  case NodeKindId.navigationStack: return .navigationStack(title: try reader.string())
  case NodeKindId.navigationDestination:
    return .navigationDestination(try RenderNavigationDestination.decode(&reader))
  case NodeKindId.semantics:
    return .semantics(try RenderSemantics.decode(&reader))
  case NodeKindId.progress:
    return .progress(try RenderProgress.decode(&reader))
  case NodeKindId.ignoresSafeArea:
    return .ignoresSafeArea(try RenderSafeArea.decode(&reader))
  case NodeKindId.safeAreaPadding:
    return .safeAreaPadding(
      leading: try reader.finiteDouble(), top: try reader.finiteDouble(),
      trailing: try reader.finiteDouble(), bottom: try reader.finiteDouble())
  case NodeKindId.empty:
    return .empty
  case NodeKindId.divider:
    return .divider
  case NodeKindId.flow: return .flow(try RenderFlow.decode(&reader))
  case NodeKindId.animatedOpacity:
    return .animatedOpacity(try RenderAnimatedOpacity.decode(&reader))
  case NodeKindId.projectionEffect: return .projection(try RenderProjection.decode(&reader))
  case NodeKindId.row:
    return .row(
      spacing: try reader.flag() ? reader.finiteDouble() : nil, alignment: try reader.choice(4))
  case NodeKindId.column:
    return .column(
      spacing: try reader.flag() ? reader.finiteDouble() : nil, alignment: try reader.choice(2))
  case NodeKindId.weightedRow, NodeKindId.weightedColumn:
    return .weighted(
      try RenderWeightedStack.decode(&reader, vertical: kind == NodeKindId.weightedColumn),
      vertical: kind == NodeKindId.weightedColumn)
  case NodeKindId.overlay:
    return .overlay(alignment: try reader.choice(8))
  case NodeKindId.stack:
    return .stack(alignment: try reader.choice(8))
  case NodeKindId.layoutPriority:
    return .layoutPriority(try reader.finiteDouble())
  case NodeKindId.offset:
    return .offset(x: try reader.finiteDouble(), y: try reader.finiteDouble())
  case NodeKindId.text:
    return .text(try reader.text())
  case NodeKindId.richText:
    return .richText(try RenderTextSpan.decode(&reader))
  case NodeKindId.symbol:
    return .symbol(try RenderSymbol.decode(&reader))
  case NodeKindId.scroll:
    return .scroll(
      vertical: try reader.flag(), indicators: try reader.flag(), fillViewport: try reader.flag(),
      initialAnchor: InitialScrollAnchor(rawValue: try reader.choice(1))!)
  case NodeKindId.collectionCatalog:
    return .collection(try RenderCollectionCatalog.decode(&reader))
  case NodeKindId.collectionWindow:
    return .collectionWindow(try RenderCollectionWindow.decode(&reader))
  case NodeKindId.textField, NodeKindId.secureField:
    return .textField(try RenderTextField.decode(&reader, secure: kind == NodeKindId.secureField))
  case NodeKindId.textEditor:
    return .textEditor(try RenderTextEditor.decode(&reader))
  case NodeKindId.image:
    return .image(try RenderImage.decode(&reader))
  case NodeKindId.frame:
    return .frame(try RenderFrame.decode(&reader))
  case NodeKindId.padding:
    return .padding(
      leading: try reader.finiteDouble(), top: try reader.finiteDouble(),
      trailing: try reader.finiteDouble(), bottom: try reader.finiteDouble())
  case NodeKindId.background:
    return .background(
      color: try reader.integer(UInt32.self), cornerRadius: try reader.nonnegativeDouble())
  case NodeKindId.clip:
    return .clip(cornerRadius: try reader.nonnegativeDouble(), antialiased: try reader.flag())
  case NodeKindId.opacity:
    let value = try reader.nonnegativeDouble()
    guard value <= 1 else { throw TreeError.invalidProperties }
    return .opacity(value)
  case NodeKindId.spacer:
    return .spacer(minLength: try reader.nonnegativeOptionalDouble())
  case NodeKindId.theme:
    return .environment(try ViewEnvironment.decode(&reader))
  case NodeKindId.controlSize: return .controlSize(try reader.choice(4))
  case NodeKindId.button:
    let enabled = try reader.flag()
    let role = try reader.choice(2)
    let style = try reader.choice(3)
    return .button(enabled: enabled, role: role, style: style, autofocus: try reader.flag())
  default:
    throw TreeError.unsupportedNode(kind)
  }
}

private func propertyMask(_ kind: Int) throws -> UInt64 {
  switch kind {
  case NodeKindId.nativeWidget: return 15
  case NodeKindId.focusScope: return 1
  case NodeKindId.keyboardListener: return 3
  case NodeKindId.empty, NodeKindId.divider, NodeKindId.label, NodeKindId.gesture: return 0
  case NodeKindId.weightedRow, NodeKindId.weightedColumn: return 7
  case NodeKindId.flow: return 7
  case NodeKindId.row, NodeKindId.column, NodeKindId.offset: return 3
  case NodeKindId.stack, NodeKindId.layoutPriority, NodeKindId.overlay: return 1
  case NodeKindId.slider: return 255
  case NodeKindId.rangeSlider: return 1023
  case NodeKindId.toggle: return 7
  case NodeKindId.badge: return 7
  case NodeKindId.sheet: return 255
  case NodeKindId.popover: return 3
  case NodeKindId.toolbar, NodeKindId.help, NodeKindId.groupBox, NodeKindId.hoverRegion: return 1
  case NodeKindId.disclosureGroup: return 3
  case NodeKindId.datePicker: return 63
  case NodeKindId.timePicker: return 15
  case NodeKindId.removal: return 63
  case NodeKindId.refresh: return 7
  case NodeKindId.scrollSections: return 63
  case NodeKindId.scrollSection: return 15
  case NodeKindId.scrollTargets: return 511
  case NodeKindId.table: return 127
  case NodeKindId.menu: return 3
  case NodeKindId.picker: return 31
  case NodeKindId.swipeActions: return 63
  case NodeKindId.swipeAction: return 255
  case NodeKindId.tabs: return 1
  case NodeKindId.tab: return 31
  case NodeKindId.morphingSurface: return 7
  case NodeKindId.navigationSplit: return 63
  case NodeKindId.navigationStack: return 1
  case NodeKindId.navigationDestination: return 7
  case NodeKindId.text: return 31
  case NodeKindId.richText: return 1
  case NodeKindId.symbol: return 15
  case NodeKindId.image: return 7
  case NodeKindId.collectionCatalog: return 1023
  case NodeKindId.collectionWindow: return 3
  case NodeKindId.scroll: return 15
  case NodeKindId.textField, NodeKindId.secureField: return 32767
  case NodeKindId.frame, NodeKindId.textEditor: return 511
  case NodeKindId.spacer, NodeKindId.padding, NodeKindId.opacity: return 1
  case NodeKindId.background, NodeKindId.clip: return 3
  case NodeKindId.animatedOpacity: return 15
  case NodeKindId.projectionEffect, NodeKindId.controlSize: return 1
  case NodeKindId.button: return 15
  case NodeKindId.semantics: return 4095
  case NodeKindId.progress: return 3
  case NodeKindId.ignoresSafeArea: return 3
  case NodeKindId.safeAreaPadding: return 1
  case NodeKindId.theme: return 1
  default: throw TreeError.unsupportedNode(kind)
  }
}

// Staging never publishes a renderer generation. The host must also validate
// all ancillary operations before committing this tree and its side effects.
struct NodeTransaction: Sendable {
  let tree: NodeStore
  let ancillaryOperations: [WireOperation]
}

struct NodeStore: Equatable, Sendable {
  var epoch: UInt64 = 0
  var revision: UInt64 = 0
  var root: UInt64?
  var nodes: [UInt64: RenderNode] = [:]
  private(set) var accessibilityHiddenNodes: Set<UInt64> = []
  private var highestNodeID: UInt64 = 0

  func staging(_ frame: WireFrame) throws -> NodeTransaction {
    let full = frame.kind == FrameKindId.fullSnapshot
    guard frame.epoch > 0, frame.epoch <= UInt64(Int64.max), frame.revision > 0,
      frame.revision <= UInt64(Int64.max)
    else { throw TreeError.revisionMismatch }
    if full {
      guard frame.baseRevision == 0, frame.epoch >= epoch,
        frame.epoch != epoch || frame.revision >= revision
      else { throw TreeError.revisionMismatch }
    } else {
      guard frame.kind == FrameKindId.incrementalFrame, frame.epoch == epoch,
        frame.baseRevision == revision, revision > 0, frame.revision == revision + 1
      else { throw TreeError.revisionMismatch }
    }

    var candidate = full ? NodeStore() : self
    candidate.epoch = frame.epoch
    candidate.revision = frame.revision
    let previousHighWater = frame.epoch == epoch ? highestNodeID : 0
    candidate.highestNodeID = previousHighWater
    var ancillary: [WireOperation] = []
    for operation in frame.operations {
      var reader = WireReader(operation.body)
      switch operation.opcode {
      case OperationId.createNode:
        let id = try reader.identity()
        guard candidate.nodes[id] == nil else { throw TreeError.duplicateNode }
        guard id > previousHighWater || (full && nodes[id] != nil)
        else { throw TreeError.invalidIdentity }
        guard candidate.nodes.count < ProtocolLimits.maxNodes else { throw WireError.limitExceeded }
        let kind = Int(try reader.integer(UInt16.self))
        let props = try properties(&reader, kind: kind)
        let bindings = try reader.bindings()
        candidate.nodes[id] = RenderNode(id: id, kind: kind, properties: props, bindings: bindings)
        candidate.highestNodeID = max(candidate.highestNodeID, id)
      case OperationId.updateProps:
        let id = try reader.identity()
        guard var node = candidate.nodes[id] else { throw TreeError.missingNode }
        let kind = Int(try reader.integer(UInt16.self))
        guard kind == node.kind, try reader.integer(UInt64.self) == propertyMask(kind)
        else { throw TreeError.invalidProperties }
        node.properties = try properties(&reader, kind: kind)
        candidate.nodes[id] = node
      case OperationId.updateEventBindings:
        let id = try reader.identity()
        guard var node = candidate.nodes[id] else { throw TreeError.missingNode }
        node.bindings = try reader.bindings()
        candidate.nodes[id] = node
      case OperationId.setChildren:
        let id = try reader.identity()
        guard var node = candidate.nodes[id] else { throw TreeError.missingNode }
        let count = Int(try reader.integer(UInt32.self))
        guard count <= ProtocolLimits.maxNodes else { throw WireError.limitExceeded }
        var children: [UInt64] = []
        for _ in 0..<count { children.append(try reader.identity()) }
        node.children = children
        candidate.nodes[id] = node
      case OperationId.setRoot:
        candidate.root = try reader.identity()
      case OperationId.dropNode:
        let id = try reader.identity()
        guard candidate.nodes.removeValue(forKey: id) != nil else { throw TreeError.missingNode }
      case OperationId.setApplicationTheme, OperationId.hostRequest,
        OperationId.applicationRequest, OperationId.runtimeNotification:
        ancillary.append(operation)
        continue
      default:
        throw WireError.invalidOperation
      }
      guard reader.remaining == 0 else { throw WireError.invalidLength }
    }
    try candidate.validateGraph()
    return NodeTransaction(tree: candidate, ancillaryOperations: ancillary)
  }

  private mutating func validateGraph() throws {
    accessibilityHiddenNodes.removeAll()
    guard let root, nodes[root] != nil else { throw TreeError.missingNode }
    var visited: Set<UInt64> = []
    var ownedWindows: Set<UInt64> = []
    var ownedDestinations: Set<UInt64> = []
    var ownedSections: Set<UInt64> = []
    var ownedTabs: Set<UInt64> = []
    var ownedSwipeActions: Set<UInt64> = []
    var pending = [(root, false)]
    // Iterative traversal also rejects duplicate parents and cycles without
    // risking a native stack overflow on a deep or malicious logical tree.
    while let (id, ancestorHidden) = pending.popLast() {
      guard visited.insert(id).inserted else { throw TreeError.invalidGraph }
      guard let node = nodes[id] else { throw TreeError.missingNode }
      let hidden = ancestorHidden || node.properties.accessibilityHidden
      if hidden { accessibilityHiddenNodes.insert(id) }
      switch node.properties {
      case .nativeView:
        guard Set(node.bindings.keys) == [EventTagId.nativeEvent] else {
          throw TreeError.invalidBindings
        }
      case .gesture:
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard
          Set(node.bindings.keys).isSubset(of: [
            EventTagId.tap, EventTagId.doubleTap,
            EventTagId.longPress, EventTagId.pointerDown, EventTagId.pointerUp,
          ])
        else { throw TreeError.invalidBindings }
      case .focusScope:
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard Set(node.bindings.keys) == [EventTagId.focusChanged] else {
          throw TreeError.invalidBindings
        }
      case .keyboardListener:
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard Set(node.bindings.keys) == [EventTagId.key] else {
          throw TreeError.invalidBindings
        }
      case .hoverRegion:
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard Set(node.bindings.keys) == [EventTagId.pointerEnter, EventTagId.pointerLeave] else {
          throw TreeError.invalidBindings
        }
      case .label:
        guard node.children.count == 2 else { throw TreeError.invalidChildren }
        guard node.bindings.isEmpty else { throw TreeError.invalidBindings }
      case .popover, .sheet:
        guard node.children.count == 2 else { throw TreeError.invalidChildren }
        guard node.bindings.count == 1, node.bindings[EventTagId.valueChanged] != nil else {
          throw TreeError.invalidBindings
        }
      case .removal:
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard Set(node.bindings.keys) == [EventTagId.removalRequested, EventTagId.removalCompleted]
        else { throw TreeError.invalidBindings }
      case .refresh:
        guard node.children.count == 1,
          nodes[node.children[0]]?.properties.scrollAxis == true
        else { throw TreeError.invalidChildren }
        guard Set(node.bindings.keys) == [EventTagId.refreshRequest] else {
          throw TreeError.invalidBindings
        }
      case .scrollSections(let properties):
        guard node.children.count <= 1024,
          Set(node.bindings.keys).isSubset(of: [EventTagId.scrollNotification])
        else {
          throw TreeError.invalidChildren
        }
        for (index, child) in node.children.enumerated() {
          guard let item = nodes[child], case .scrollSection(let section) = item.properties,
            section.heroHeight == nil || (properties.vertical && index == 0)
          else { throw TreeError.invalidChildren }
          ownedSections.insert(child)
        }
      case .scrollSection(let properties):
        guard ownedSections.contains(id), node.children.count >= 2, node.bindings.isEmpty,
          properties.heroHeight == nil || node.children.count == 3
        else { throw TreeError.invalidChildren }
      case .toolbar(let properties):
        guard node.children.count == properties.placements.count + 1, node.bindings.isEmpty
        else { throw TreeError.invalidChildren }
      case .groupBox(let hasLabel):
        guard node.children.count == (hasLabel ? 2 : 1) else { throw TreeError.invalidChildren }
        guard node.bindings.isEmpty else { throw TreeError.invalidBindings }
      case .slider(let properties):
        guard node.children.isEmpty else { throw TreeError.invalidChildren }
        let range = properties.selection.upper != nil
        let changed = range ? EventTagId.rangeSliderChanged : EventTagId.sliderChanged
        let ended = range ? EventTagId.rangeSliderChangeEnd : EventTagId.sliderChangeEnd
        if properties.enabled {
          guard node.bindings.count == (properties.changes ? 2 : 1), node.bindings[ended] != nil,
            (node.bindings[changed] != nil) == properties.changes
          else { throw TreeError.invalidBindings }
        } else if !node.bindings.isEmpty {
          throw TreeError.invalidBindings
        }
      case .civilPicker(let properties):
        guard node.children.isEmpty else { throw TreeError.invalidChildren }
        guard
          properties.enabled
            ? node.bindings.count == 1 && node.bindings[properties.tag] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .scrollTargets(let properties):
        guard node.children.count == properties.ids.count else { throw TreeError.invalidChildren }
        let required: Set<Int> = properties.enabled ? [EventTagId.scrollPositionChanged] : []
        let tags = Set(node.bindings.keys)
        guard required.isSubset(of: tags),
          tags.isSubset(of: required.union([EventTagId.scrollNotification]))
        else { throw TreeError.invalidBindings }
      case .table(let properties):
        guard node.children.count == properties.childCount else { throw TreeError.invalidChildren }
        var required = Set<Int>()
        if properties.hasSort { required.insert(EventTagId.tableSortRequested) }
        if properties.hasSelection { required.insert(EventTagId.tableRowSelected) }
        guard Set(node.bindings.keys) == required else { throw TreeError.invalidBindings }
      case .menu(let properties):
        guard node.children.count == properties.labelCount else { throw TreeError.invalidChildren }
        guard
          properties.enabled
            ? node.bindings.count == 1 && node.bindings[EventTagId.menuAction] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .picker(let properties):
        guard node.children.count == properties.options.filter({ $0.childIndex != nil }).count
        else {
          throw TreeError.invalidChildren
        }
        guard
          properties.enabled
            ? node.bindings.count == 1 && node.bindings[EventTagId.pickerSelected] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .booleanControl(let properties):
        guard node.children.count == (properties.style == .disclosure ? 2 : 1)
        else { throw TreeError.invalidChildren }
        guard
          properties.enabled
            ? node.bindings.count == 1 && node.bindings[EventTagId.valueChanged] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .swipeActions:
        guard node.bindings.isEmpty, !node.children.isEmpty, node.children.count <= 65 else {
          throw TreeError.invalidChildren
        }
        if let first = nodes[node.children[0]], case .swipeAction = first.properties {
          throw TreeError.invalidChildren
        }
        var fullSides = Set<Int>()
        for child in node.children.dropFirst() {
          guard let action = nodes[child], case .swipeAction(let p) = action.properties else {
            throw TreeError.invalidChildren
          }
          if p.fullSwipe && !fullSides.insert(p.side).inserted { throw TreeError.invalidProperties }
          ownedSwipeActions.insert(child)
        }
      case .swipeAction(let p):
        guard ownedSwipeActions.contains(id), node.children.count == 1 else {
          throw TreeError.invalidChildren
        }
        guard
          p.enabled
            ? node.bindings.count == 1 && node.bindings[EventTagId.press] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .tabs(let selection):
        guard node.bindings.count == 1, node.bindings[EventTagId.tabSelected] != nil else {
          throw TreeError.invalidBindings
        }
        guard !node.children.isEmpty, node.children.count <= 256 else {
          throw TreeError.invalidChildren
        }
        var keys = Set<RenderTabKey>()
        for child in node.children {
          guard let item = nodes[child], case .tab(let tab) = item.properties,
            keys.insert(tab.key).inserted
          else { throw TreeError.invalidChildren }
          ownedTabs.insert(child)
        }
        guard keys.contains(selection) else { throw TreeError.invalidProperties }
      case .tab:
        guard ownedTabs.contains(id), node.children.count == 1, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .navigationSplit(let properties):
        guard node.children.count == (properties.contentTitle == nil ? 2 : 3) else {
          throw TreeError.invalidChildren
        }
        guard node.bindings.count == 1, node.bindings[EventTagId.navigationSplitChanged] != nil
        else { throw TreeError.invalidBindings }
      case .navigationStack:
        guard node.bindings.count == 1, node.bindings[EventTagId.navigationPathChanged] != nil
        else { throw TreeError.invalidBindings }
        guard !node.children.isEmpty, node.children.count <= 257,
          let first = nodes[node.children[0]]
        else { throw TreeError.invalidChildren }
        if case .navigationDestination = first.properties { throw TreeError.invalidChildren }
        var keys = Set<Data>()
        for child in node.children.dropFirst() {
          guard let destination = nodes[child],
            case .navigationDestination(let properties) = destination.properties,
            keys.insert(Data(properties.key.utf8)).inserted
          else { throw TreeError.invalidChildren }
          ownedDestinations.insert(child)
        }
      case .navigationDestination:
        guard ownedDestinations.contains(id), node.children.count == 1, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .semantics(let properties):
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard
          properties.actions.isEmpty
            ? node.bindings.isEmpty
            : node.bindings.count == 1 && node.bindings[EventTagId.semanticsAction] != nil
        else { throw TreeError.invalidBindings }
      case .collection(let catalog):
        guard node.bindings[EventTagId.visibleRangeChanged] != nil,
          Set(node.bindings.keys).isSubset(of: [
            EventTagId.visibleRangeChanged, EventTagId.scrollNotification,
          ])
        else {
          throw TreeError.invalidBindings
        }
        guard node.children.count == 1, let window = nodes[node.children[0]],
          case .collectionWindow(let properties) = window.properties,
          properties.firstIndex <= catalog.keys.count,
          properties.keys.count <= catalog.keys.count - properties.firstIndex,
          properties.keys
            == Array(
              catalog.keys[properties.firstIndex..<(properties.firstIndex + properties.keys.count)])
        else { throw TreeError.invalidChildren }
        ownedWindows.insert(window.id)
      case .collectionWindow(let window):
        guard ownedWindows.contains(id), node.children.count == window.keys.count,
          node.bindings.isEmpty
        else { throw TreeError.invalidChildren }
      case .morphingSurface:
        guard node.children.count == 1, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .overlay:
        guard node.children.count == 2, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .weighted(let stack, _):
        guard stack.items.count == node.children.count, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .animatedOpacity:
        guard node.children.count == 1, node.bindings.count == 1,
          node.bindings[EventTagId.animationCompleted] != nil
        else { throw TreeError.invalidBindings }
      case .help, .badge, .projection, .controlSize, .ignoresSafeArea, .safeAreaPadding,
        .environment,
        .frame,
        .padding, .background,
        .clip, .opacity, .layoutPriority,
        .offset:
        guard node.children.count == 1, node.bindings.isEmpty else {
          throw TreeError.invalidChildren
        }
      case .scroll:
        guard node.children.count == 1,
          Set(node.bindings.keys).isSubset(of: [EventTagId.scrollNotification])
        else { throw TreeError.invalidBindings }
      case .button(let enabled, _, _, _):
        guard node.children.count == 1 else { throw TreeError.invalidChildren }
        guard
          enabled
            ? node.bindings.count == 1 && node.bindings[EventTagId.press] != nil
            : node.bindings.isEmpty
        else { throw TreeError.invalidBindings }
      case .textEditor, .textField:
        let required: Set<Int> = [
          EventTagId.textEdit, EventTagId.textSubmit, EventTagId.focusChanged,
        ]
        let tags = Set(node.bindings.keys)
        guard required.isSubset(of: tags),
          tags.isSubset(of: required.union([EventTagId.textLimitReached]))
        else { throw TreeError.invalidBindings }
        guard node.children.isEmpty else { throw TreeError.invalidChildren }
      case .progress, .empty, .divider, .text, .richText, .symbol, .image, .spacer:
        guard node.bindings.isEmpty else { throw TreeError.invalidBindings }
        guard node.children.isEmpty else { throw TreeError.invalidChildren }
      case .flow, .row, .column, .stack:
        guard node.bindings.isEmpty else { throw TreeError.invalidBindings }
      }
      let childrenHidden: Bool
      if case .semantics(let properties) = node.properties {
        childrenHidden = hidden || properties.children == 2
      } else if case .swipeAction = node.properties {
        childrenHidden = true
      } else {
        childrenHidden = hidden
      }
      pending.append(
        contentsOf: node.children.enumerated().map { index, child in
          let inactive: Bool
          if case .sheet(let sheet) = node.properties {
            inactive = index == (sheet.presented ? 0 : 1)
          } else if case .popover(let popover) = node.properties {
            inactive = index == 1 && !popover.presented
          } else if case .booleanControl(let control) = node.properties,
            control.style == .disclosure
          {
            inactive = index == 1 && !control.value
          } else {
            inactive = false
          }
          return (child, childrenHidden || inactive)
        })
    }
    guard visited.count == nodes.count else { throw TreeError.invalidGraph }
  }
}
