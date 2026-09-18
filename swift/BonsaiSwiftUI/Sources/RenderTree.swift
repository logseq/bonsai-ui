import Observation
import SwiftUI

struct RenderIdentity: Hashable, Sendable {
  let epoch: UInt64
  let node: UInt64
}

struct ButtonActivation: Equatable, Sendable {
  let identity: RenderIdentity
  let revision: UInt64
  let handler: UInt64
}

@MainActor @Observable
final class RenderNodeState: Identifiable, Equatable {
  let id: RenderIdentity
  let kind: Int
  var properties: NodeProperties
  var bindings: [Int: UInt64]
  var children: [RenderNodeState] = []
  let emit: (NativeEventPayload) -> Bool
  var accessibilityHidden = false
  var progressAnimationsActive = true
  let layoutTarget: NodeLayoutTarget
  let imageResource: ImageResource?
  let textController: NativeTextController?
  let fieldController: NativeTextFieldController?
  let collectionController: CollectionController?
  let navigationController: NavigationStackController?
  let splitController: NavigationSplitController?
  let swipeController: SwipeActionsController?
  @ObservationIgnored weak var swipeActionOwner: SwipeActionsController?
  let opacityController: AnimatedOpacityController?
  let morphingSurfaceController: MorphingSurfaceController?
  let tabsController: TabsController?
  let booleanControlController: BooleanControlController?
  let presentationController: PresentationController?
  let civilPickerController: CivilPickerController?
  let removalController: RemovalController?
  let listVisibility: ListVisibility?
  let refreshController: RefreshController?
  let scrollObserver: ScrollObserver?
  let scrollCommand: NativeScrollCommand?
  let scrollTargetsController: ScrollTargetsController?
  let tableController: NativeTableController?
  let menuController: NativeMenuController?
  let pickerController: PickerController?
  let sliderController: SliderController?
  let hoverController: HoverRegionController?
  let gestureController: NativeGestureController?
  let focusController: FocusScopeController?
  let keyboardController: KeyboardListenerController?
  var nativeView: NativeViewInstance?

  func setPresentationChange(_ changed: (() -> Void)?) {
    nativeView?.onPresentationChange = changed
    presentationController?.onPresentationChange = changed
    booleanControlController?.onPresentationChange = changed
    tabsController?.onPresentationChange = changed
    navigationController?.onPresentationChange = changed
    tableController?.onPresentationChange = changed
    removalController?.onPresentationChange = changed
  }

  init(
    epoch: UInt64, node: RenderNode, imageLoader: any ImageLoading,
    imageClock: @escaping @Sendable () -> ContinuousClock.Instant,
    hoverHost: NativeHoverHost,
    input: @escaping (RenderIdentity, NativeEventPayload) -> Bool,
    failed: @escaping (any Error) -> Void
  ) {
    id = RenderIdentity(epoch: epoch, node: node.id)
    layoutTarget = NodeLayoutTarget(identity: id)
    let identity = RenderIdentity(epoch: epoch, node: node.id)
    emit = { input(identity, $0) }
    kind = node.kind
    properties = node.properties
    if case .removal(let properties) = node.properties {
      removalController = RemovalController(properties, emit: { input(identity, $0) })
    } else {
      removalController = nil
    }
    listVisibility = node.properties == .nativeList ? ListVisibility() : nil
    if case .refresh(let properties) = node.properties {
      refreshController = RefreshController(properties, emit: { input(identity, $0) })
    } else {
      refreshController = nil
    }
    scrollCommand = node.properties.scrollAxis.map { NativeScrollCommand(vertical: $0) }
    scrollObserver = node.properties.scrollAxis.map {
      ScrollObserver(
        vertical: $0, handler: node.bindings[EventTagId.scrollNotification],
        emit: { input(identity, $0) })
    }
    if case .focusScope(let autofocus) = node.properties {
      focusController = FocusScopeController(
        autofocus: autofocus, handler: node.bindings[EventTagId.focusChanged],
        emit: { input(identity, $0) })
    } else if case .button(_, _, _, let autofocus) = node.properties {
      focusController = FocusScopeController(
        autofocus: autofocus, handler: nil, emit: { _ in false })
    } else {
      focusController = nil
    }
    if case .keyboardListener(let properties) = node.properties {
      keyboardController = KeyboardListenerController(
        id: identity, properties: properties, handler: node.bindings[EventTagId.key],
        emit: { input(identity, $0) })
    } else {
      keyboardController = nil
    }
    if case .gesture = node.properties {
      gestureController = NativeGestureController(
        bindings: node.bindings, emit: { input(identity, $0) })
    } else {
      gestureController = nil
    }
    if case .hoverRegion = node.properties {
      hoverController = HoverRegionController(
        id: identity, host: hoverHost, emit: { input(identity, $0) })
    } else {
      hoverController = nil
    }
    if case .image(let image) = node.properties {
      imageResource = ImageResource(source: image.source, loader: imageLoader, clock: imageClock)
    } else {
      imageResource = nil
    }
    if case .collection(let catalog) = node.properties {
      collectionController = CollectionController(catalog)
    } else {
      collectionController = nil
    }
    if case .navigationStack = node.properties {
      navigationController = NavigationStackController()
    } else {
      navigationController = nil
    }
    if case .navigationSplit(let properties) = node.properties {
      splitController = NavigationSplitController(
        properties.state, hasContent: properties.contentTitle != nil)
    } else {
      splitController = nil
    }
    if case .tabs(let selection) = node.properties {
      tabsController = TabsController(selection)
    } else {
      tabsController = nil
    }
    if case .animatedOpacity(let properties) = node.properties {
      opacityController = AnimatedOpacityController(properties, emit: { input(identity, $0) })
    } else {
      opacityController = nil
    }
    if case .morphingSurface(let properties) = node.properties {
      morphingSurfaceController = MorphingSurfaceController(properties)
    } else {
      morphingSurfaceController = nil
    }
    if case .swipeActions(let properties) = node.properties {
      swipeController = SwipeActionsController(identity: identity, properties: properties)
    } else {
      swipeController = nil
    }
    if case .civilPicker(let properties) = node.properties {
      civilPickerController = CivilPickerController(properties)
    } else {
      civilPickerController = nil
    }
    if case .scrollTargets(let properties) = node.properties {
      scrollTargetsController = ScrollTargetsController(properties)
    } else {
      scrollTargetsController = nil
    }
    if case .table(let properties) = node.properties {
      tableController = NativeTableController(properties)
    } else {
      tableController = nil
    }
    if case .menu(let properties) = node.properties {
      menuController = NativeMenuController(properties)
    } else {
      menuController = nil
    }
    if case .picker(let properties) = node.properties {
      pickerController = PickerController(properties)
    } else {
      pickerController = nil
    }
    if let properties = node.properties.presentation {
      presentationController = PresentationController(properties)
    } else {
      presentationController = nil
    }
    if case .booleanControl(let properties) = node.properties {
      booleanControlController = BooleanControlController(properties)
    } else {
      booleanControlController = nil
    }
    if case .slider(let properties) = node.properties {
      sliderController = SliderController(properties)
    } else {
      sliderController = nil
    }
    if case .textField(let properties) = node.properties {
      fieldController = NativeTextFieldController(
        snapshot: properties.editing.snapshot, secure: properties.secure,
        configuration: properties.editing.configuration,
        label: properties.label, prompt: properties.prompt,
        emit: { input(identity, $0) }, failed: failed)
      fieldController?.configureTraits(properties.traits)
    } else {
      fieldController = nil
    }
    bindings = node.bindings
    if case .textEditor(let editor) = node.properties {
      let identity = RenderIdentity(epoch: epoch, node: node.id)
      textController = NativeTextController(
        snapshot: editor.snapshot, configuration: editor.configuration,
        emit: { input(identity, $0) }, failed: failed)
      textController?.configureAutofocus(editor.autofocus)
    } else {
      textController = nil
    }
  }

  nonisolated static func == (lhs: RenderNodeState, rhs: RenderNodeState) -> Bool {
    lhs === rhs
  }
}

@MainActor @Observable
final class RenderTree {
  let hoverRouter = HoverRouter()
  private let hoverHost: NativeHoverHost
  private let keyboardHost = NativeKeyboardHost()
  var activeHoverWindowCount: Int { hoverHost.activeWindowCount }
  func discardHoverInput() {
    hoverRouter.discardSamples()
    hoverHost.discardInput()
  }
  private(set) var root: RenderNodeState?
  private(set) var nodes: [UInt64: RenderNodeState] = [:]
  private(set) var nativeViewNodes: [RenderNodeState] = []
  private(set) var presentationNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var fieldNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var listNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var collectionNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var focusAndGestureNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var scrollNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var hoverNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var opacityNodes: [RenderNodeState] = []
  @ObservationIgnored private(set) var animationNodes: [RenderNodeState] = []
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  @ObservationIgnored private var committing = false
  private func presentationChanged() {
    if !committing { onPresentationChange?() }
  }
  @ObservationIgnored private(set) var parents: [UInt64: UInt64] = [:]
  private(set) var epoch: UInt64 = 0
  private(set) var revision: UInt64 = 0

  @ObservationIgnored var onInput: ((RenderNodeState, NativeEventPayload) -> Bool)?
  @ObservationIgnored var onInteractionPermission: ((RenderNodeState) -> Bool)?
  @ObservationIgnored var onInputFailure: ((any Error) -> Void)?
  private let nativeViews: BonsaiNativeViews
  @ObservationIgnored private var preparedViews: [UInt64: PreparedNativeView] = [:]
  @ObservationIgnored private var preparedRevision: UInt64 = 0
  @ObservationIgnored private var preparedEpoch: UInt64 = 0
  private let imageLoader: any ImageLoading
  private let imageClock: @Sendable () -> ContinuousClock.Instant

  init(
    nativeViews: BonsaiNativeViews = BonsaiNativeViews(),
    imageLoader: any ImageLoading = ImageLoader(),
    imageClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
  ) {
    self.nativeViews = nativeViews.includingStandardViews()
    hoverHost = NativeHoverHost(router: hoverRouter)
    self.imageLoader = imageLoader
    self.imageClock = imageClock
  }

  func validate(_ store: NodeStore) throws {
    var prepared: [UInt64: PreparedNativeView] = [:]
    for (id, node) in store.nodes {
      if case .nativeView(let envelope) = node.properties {
        if epoch == store.epoch, let existing = nodes[id]?.nativeView,
          existing.prepared.envelope == envelope
        {
          prepared[id] = existing.prepared
        } else {
          prepared[id] = try nativeViews.prepare(envelope)
        }
        let value = prepared[id]!
        try value.definition.validateChildren(value.properties, node.children.count)
      }
      if epoch == store.epoch, let editor = node.properties.textEditing,
        var session = nodes[id]?.textController?.session ?? nodes[id]?.fieldController?.session
      {
        _ = try session.apply(editor.snapshot)
      }
    }
    preparedViews = prepared
    preparedRevision = store.revision
    preparedEpoch = store.epoch
  }

  func commit(_ store: NodeStore) {
    committing = true
    defer {
      committing = false
      onPresentationChange?()
    }
    var next: [UInt64: RenderNodeState] = [:]
    for (id, node) in store.nodes {
      if epoch == store.epoch, let existing = nodes[id], existing.kind == node.kind {
        next[id] = existing
      } else {
        next[id] = RenderNodeState(
          epoch: store.epoch, node: node, imageLoader: imageLoader, imageClock: imageClock,
          hoverHost: hoverHost,
          input: { [weak self] identity, payload in
            guard let self, let node = self.nodes[identity.node], node.id == identity else {
              return false
            }
            return self.onInput?(node, payload) ?? false
          }, failed: { [weak self] error in self?.onInputFailure?(error) })
      }
    }
    parents.removeAll(keepingCapacity: true)
    // No suspension occurs during publication. SwiftUI observes only fields
    // read by each node's body; unchanged siblings retain their objects.
    for (id, node) in store.nodes {
      guard let state = next[id] else { preconditionFailure("Validated node missing") }
      if case .nativeView = node.properties {
        guard preparedEpoch == store.epoch, preparedRevision == store.revision,
          let prepared = preparedViews[id]
        else { preconditionFailure("Native views must validate before commit") }
        if let instance = state.nativeView, instance.prepared.definition === prepared.definition {
          instance.synchronize(prepared, node: node)
        } else {
          state.nativeView?.dispose()
          state.nativeView = NativeViewInstance(prepared, node: node, emit: state.emit)
          state.nativeView?.canInteract = { [weak self, weak state] in
            guard let self, let state else { return false }
            return self.onInteractionPermission?(state) ?? false
          }
        }
      }
      if state.properties != node.properties {
        state.properties = node.properties
        if case .animatedOpacity(let properties) = node.properties {
          state.opacityController?.replace(properties)
        }
        if case .morphingSurface(let properties) = node.properties {
          state.morphingSurfaceController?.replace(properties)
        }
        if case .collection(let catalog) = node.properties {
          state.collectionController?.replace(catalog)
        }
        if case .image(let image) = node.properties {
          state.imageResource?.replace(with: image.source)
        }
        if case .textField(let field) = node.properties {
          state.fieldController?.setPresentationActive(false)
          do { try state.fieldController?.apply(field.editing.snapshot) } catch {
            preconditionFailure("Text updates must validate before commit")
          }
          state.fieldController?.configure(field.editing.configuration)
          state.fieldController?.setLabels(label: field.label, prompt: field.prompt)
          state.fieldController?.configureTraits(field.traits)
        }
        if case .textEditor(let editor) = node.properties {
          state.textController?.setPresentationActive(false)
          do { try state.textController?.apply(editor.snapshot) } catch {
            preconditionFailure("Text updates must validate before commit")
          }
          state.textController?.configure(editor.configuration)
          state.textController?.configureAutofocus(editor.autofocus)
        }
      }
      state.accessibilityHidden = store.accessibilityHiddenNodes.contains(id)
      if state.bindings != node.bindings {
        state.removalController?.invalidateBinding()
        state.refreshController?.invalidateBinding()
        state.presentationController?.invalidateBinding()
        state.scrollTargetsController?.invalidateBinding()
        state.menuController?.invalidateBinding()
        state.tableController?.invalidateBinding()
        state.civilPickerController?.invalidateBinding()
        state.bindings = node.bindings
      }
      let children = node.children.map {
        guard let child = next[$0] else { preconditionFailure("Validated child missing") }
        return child
      }
      if state.children != children {
        state.presentationController?.invalidateBinding()
        state.scrollTargetsController?.invalidateBinding()
        state.menuController?.invalidateBinding()
        state.tableController?.invalidateBinding()
        state.children = children
      }
      for child in children { parents[child.id.node] = id }
    }
    for state in next.values {
      state.layoutTarget.contentChanged()
      if case .keyboardListener(let properties) = state.properties {
        state.keyboardController?.synchronize(properties, handler: state.bindings[EventTagId.key])
      }
      if case .focusScope(let autofocus) = state.properties {
        state.focusController?.synchronize(
          autofocus: autofocus, handler: state.bindings[EventTagId.focusChanged])
      } else if case .button(_, _, _, let autofocus) = state.properties {
        state.focusController?.synchronize(autofocus: autofocus, handler: nil)
      }
      state.gestureController?.synchronize(state.bindings)
      if let vertical = state.properties.scrollAxis {
        state.scrollCommand?.synchronize(vertical: vertical)
        state.scrollObserver?.synchronize(
          vertical: vertical, handler: state.bindings[EventTagId.scrollNotification])
      }
      if case .swipeActions(let properties) = state.properties,
        let controller = state.swipeController
      {
        controller.synchronize(properties, actions: Array(state.children.dropFirst()))
        for action in state.children.dropFirst() { action.swipeActionOwner = controller }
      }
      if case .tabs(let selection) = state.properties {
        state.tabsController?.synchronize(selection, children: state.children)
      }
      if case .civilPicker(let properties) = state.properties {
        state.civilPickerController?.synchronize(properties)
      }
      if case .removal(let properties) = state.properties {
        state.removalController?.synchronize(properties)
      }
      state.listVisibility?.synchronize(
        state.children.flatMap { Array($0.children.dropFirst(2)).map(\.id) },
        handler: state.bindings[EventTagId.visibleRangeChanged])
      if case .refresh(let properties) = state.properties {
        state.refreshController?.synchronize(properties)
      }
      if case .scrollTargets(let properties) = state.properties {
        state.scrollTargetsController?.synchronize(properties)
      }
      if case .table(let properties) = state.properties {
        state.tableController?.synchronize(properties)
      }
      if case .menu(let properties) = state.properties {
        state.menuController?.synchronize(properties)
      }
      if case .picker(let properties) = state.properties {
        state.pickerController?.synchronize(properties)
      }
      if let properties = state.properties.presentation {
        state.presentationController?.setContentIdentity(state.children.last?.id)
        state.presentationController?.synchronize(properties)
      }
      if case .booleanControl(let properties) = state.properties {
        state.booleanControlController?.synchronize(properties)
      }
      if case .slider(let properties) = state.properties {
        state.sliderController?.synchronize(properties)
      }
      state.navigationController?.synchronize(state.children)
      if case .navigationSplit(let properties) = state.properties {
        state.splitController?.synchronize(
          properties.state, hasContent: properties.contentTitle != nil)
      }
      if let controller = state.collectionController, let window = state.children.first,
        case .collectionWindow(let properties) = window.properties
      {
        controller.synchronize(properties, rows: window.children.map(\.id))
      }
    }
    for (id, old) in nodes where next[id] !== old {
      old.setPresentationChange(nil)
      old.layoutTarget.dispose()
      old.nativeView?.dispose()
      old.imageResource?.cancel()
      old.textController?.dispose()
      old.fieldController?.dispose()
      old.collectionController?.dispose()
      old.navigationController?.dispose()
      old.splitController?.dispose()
      old.swipeController?.dispose()
      old.tabsController?.dispose()
      old.booleanControlController?.dispose()
      old.presentationController?.dispose()
      old.civilPickerController?.dispose()
      old.scrollTargetsController?.dispose()
      old.removalController?.dispose()
      old.refreshController?.dispose()
      old.scrollObserver?.dispose()
      old.scrollCommand?.dispose()
      old.menuController?.dispose()
      old.tableController?.dispose()
      old.pickerController?.dispose()
      old.sliderController?.dispose()
      old.opacityController?.dispose()
      old.morphingSurfaceController?.dispose()
      old.hoverController?.dispose()
      old.gestureController?.dispose()
      old.focusController?.dispose()
      old.keyboardController?.dispose()
    }
    preparedViews.removeAll()
    nodes = next
    nativeViewNodes = []
    presentationNodes = []
    fieldNodes = []
    listNodes = []
    collectionNodes = []
    focusAndGestureNodes = []
    scrollNodes = []
    hoverNodes = []
    opacityNodes = []
    animationNodes = []
    epoch = store.epoch
    revision = store.revision
    let newRoot = store.root.flatMap { next[$0] }
    if root !== newRoot { root = newRoot }
    var regions: [HoverRouter.Region] = []
    var pending = root.map { [($0, false)] } ?? []
    var starts: [RenderIdentity: Int] = [:]
    var order = 0
    while let (node, exiting) = pending.popLast() {
      if exiting {
        if case .hoverRegion(let blocksBehind) = node.properties,
          let controller = node.hoverController,
          let start = starts[node.id]
        {
          controller.synchronize(node.bindings)
          regions.append(
            controller.region(subtree: start..<order, order: start, blocksBehind: blocksBehind))
        }
      } else {
        node.setPresentationChange { [weak self] in self?.presentationChanged() }
        if node.nativeView != nil { nativeViewNodes.append(node) }
        if node.presentationController != nil { presentationNodes.append(node) }
        if node.fieldController != nil || node.textController != nil { fieldNodes.append(node) }
        if node.listVisibility != nil { listNodes.append(node) }
        if node.collectionController != nil { collectionNodes.append(node) }
        if node.focusController != nil || node.keyboardController != nil
          || node.gestureController != nil
        {
          focusAndGestureNodes.append(node)
        }
        if node.removalController != nil || node.refreshController != nil
          || node.scrollCommand != nil || node.scrollObserver != nil
        {
          scrollNodes.append(node)
        }
        if node.hoverController != nil { hoverNodes.append(node) }
        if node.opacityController != nil { opacityNodes.append(node) }
        if node.collectionController != nil || node.morphingSurfaceController != nil {
          animationNodes.append(node)
        }
        starts[node.id] = order
        order += 1
        pending.append((node, true))
        for child in node.children.reversed() { pending.append((child, false)) }
      }
    }
    fieldNodes.sort { $0.id.node < $1.id.node }
    collectionNodes.sort { $0.id.node < $1.id.node }
    hoverRouter.replace(regions)
    keyboardHost.replace(next.values.compactMap(\.keyboardController), parents: parents)
  }
}

struct NativeNodeView: View {
  @Environment(\.bonsaiRowSpacing) private var rowSpacing
  @Environment(\.bonsaiDefaults) private var defaults
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    identifiedContent.modifier(NativeLayoutPublisher(target: node.layoutTarget))
  }

  private var identifiedContent: AnyView {
    // Child collections already key every logical node. Apply an explicit ID
    // only where native view state needs ownership: IDView introduces a layout
    // boundary that otherwise changes Spacer behavior inside modifiers.
    switch node.properties {
    case .nativeList, .listSection, .listRow, .table, .removal, .refresh, .scrollSections, .sheet,
      .popover, .scrollTargets, .menu,
      .civilPicker,
      .picker,
      .slider,
      .booleanControl,
      .button,
      .scroll,
      .collection,
      .textEditor, .textField,
      .image,
      .progress,
      .navigationStack,
      .navigationSplit, .tabs, .morphingSurface, .swipeActions:
      return AnyView(content.id(node.id))
    default:
      return AnyView(content)
    }
  }

  private var child: NativeNodeView {
    NativeNodeView(node: node.children[0], activate: activate)
  }

  @ViewBuilder private var children: some View {
    ForEach(node.children) { child in
      NativeNodeView(node: child, activate: activate)
    }
  }

  private var content: AnyView {
    switch node.properties {
    case .nativeView:
      guard let instance = node.nativeView else { preconditionFailure("Missing native view") }
      return AnyView(
        NativeRegisteredView(instance: instance, children: node.children, activate: activate).id(
          instance.id))
    case .keyboardListener:
      guard let controller = node.keyboardController else {
        preconditionFailure("Missing keyboard listener controller")
      }
      return AnyView(NativeKeyboardListener(controller: controller, content: child).id(node.id))
    case .focusScope:
      guard let controller = node.focusController else {
        preconditionFailure("Missing focus scope controller")
      }
      return AnyView(NativeFocusScope(controller: controller, content: child).id(node.id))
    case .gesture:
      guard let controller = node.gestureController else {
        preconditionFailure("Missing gesture controller")
      }
      return AnyView(NativeGestureContent(controller: controller, content: child).id(node.id))
    case .hoverRegion:
      guard let controller = node.hoverController else {
        preconditionFailure("Missing hover controller")
      }
      return AnyView(child.background(NativeHoverRegion(controller: controller).id(node.id)))
    case .nativeList:
      return AnyView(NativeList(node: node, activate: activate))
    case .listRow:
      return AnyView(NativeNodeView(node: node.children[0], activate: activate))
    case .listSection:
      return AnyView(EmptyView())
    case .swipeActions:
      guard let controller = node.swipeController else {
        preconditionFailure("Missing swipe controller")
      }
      return AnyView(NativeSwipeActions(node: node, controller: controller, activate: activate))
    case .swipeAction:
      guard let controller = node.swipeActionOwner else {
        preconditionFailure("Missing swipe owner")
      }
      return AnyView(NativeSwipeAction(node: node, controller: controller, activate: activate))
    case .morphingSurface(let properties):
      guard let controller = node.morphingSurfaceController else {
        preconditionFailure("Missing morphing surface controller")
      }
      return AnyView(
        NativeMorphingSurface(
          node: node, properties: properties,
          controller: controller, activate: activate))
    case .tabs:
      guard let controller = node.tabsController else {
        preconditionFailure("Missing tabs controller")
      }
      return AnyView(NativeTabs(node: node, controller: controller, activate: activate))
    case .tab:
      return AnyView(child)
    case .navigationSplit(let properties):
      guard let controller = node.splitController else {
        preconditionFailure("Missing split controller")
      }
      return AnyView(
        NativeNavigationSplit(
          node: node, properties: properties, controller: controller, activate: activate))
    case .navigationStack(let title):
      guard let controller = node.navigationController else {
        preconditionFailure("Missing navigation controller")
      }
      return AnyView(
        NativeNavigationStack(node: node, title: title, controller: controller, activate: activate))
    case .navigationDestination(let properties):
      return AnyView(
        child.navigationTitle(properties.title).navigationBarBackButtonHidden(!properties.canPop))
    case .ignoresSafeArea(let properties):
      return AnyView(child.ignoresSafeArea(properties.nativeRegions, edges: properties.nativeEdges))
    case .safeAreaPadding(let leading, let top, let trailing, let bottom):
      return AnyView(
        child.safeAreaPadding(
          EdgeInsets(
            top: CGFloat(top), leading: CGFloat(leading),
            bottom: CGFloat(bottom), trailing: CGFloat(trailing))))
    case .progress(let properties):
      return AnyView(
        NativeProgressView(properties: properties))
    case .semantics(let properties):
      return AnyView(
        child.modifier(NativeSemanticsModifier(properties: properties, emit: node.emit)))
    case .scrollTargets(let properties):
      return AnyView(
        NativeScrollTargets(
          node: node, properties: properties,
          controller: node.scrollTargetsController!, activate: activate))
    case .scroll(let vertical, let indicators, let fillViewport, let initialAnchor):
      return AnyView(
        NativeScroll(
          node: node, vertical: vertical, indicators: indicators,
          fillViewport: fillViewport, initialAnchor: initialAnchor, activate: activate))
    case .collection:
      guard let controller = node.collectionController else {
        preconditionFailure("Missing collection controller")
      }
      return AnyView(
        NativeCollectionNodeView(node: node, controller: controller, activate: activate))
    case .collectionWindow:
      return AnyView(children)
    case .textField(let properties):
      guard let controller = node.fieldController else {
        preconditionFailure("Missing field controller")
      }
      return AnyView(
        NativeTextFieldView(controller: controller)
          .disabled(!properties.editing.configuration.enabled))
    case .textEditor:
      guard let controller = node.textController else {
        preconditionFailure("Missing text controller")
      }
      return AnyView(NativeTextEditorView(controller: controller))
    case .badge(let properties):
      return AnyView(NativeBadge(properties: properties, content: child))
    case .label:
      return AnyView(
        Label {
          child
        } icon: {
          NativeNodeView(node: node.children[1], activate: activate)
            .environment(\.bonsaiLabelIcon, true)
        })
    case .sheet(let properties):
      return AnyView(
        NativeSheet(
          node: node, controller: node.presentationController!, properties: properties,
          activate: activate))
    case .popover(let properties):
      return AnyView(
        NativePopover(
          node: node, controller: node.presentationController!, properties: properties,
          activate: activate))
    case .removal:
      return AnyView(
        NativeRemoval(node: node, controller: node.removalController!, activate: activate))
    case .refresh:
      return AnyView(
        NativeRefresh(node: node, controller: node.refreshController!, activate: activate))
    case .scrollSections(let properties):
      return AnyView(NativeScrollSections(node: node, properties: properties, activate: activate))
    case .scrollSection:
      preconditionFailure("Sections must be rendered by their scroll container")
    case .toolbar(let properties):
      return AnyView(NativeToolbar(node: node, properties: properties, activate: activate))
    case .help(let message):
      return AnyView(child.help(Text(verbatim: message)))
    case .groupBox(let hasLabel):
      if hasLabel {
        return AnyView(
          GroupBox {
            child
          } label: {
            NativeNodeView(node: node.children[1], activate: activate)
          })
      }
      return AnyView(GroupBox { child })
    case .divider:
      return AnyView(Divider())
    case .empty:
      return AnyView(EmptyView())
    case .flow(let properties):
      return AnyView(NativeFlowLayout(properties: properties) { children })
    case .row(let spacing, let alignment):
      return AnyView(
        HStack(
          alignment: nativeVerticalAlignment(alignment),
          spacing: (spacing ?? rowSpacing).map { CGFloat($0) }
        ) {
          children
        })
    case .column(let spacing, let alignment):
      return AnyView(
        VStack(
          alignment: nativeHorizontalAlignment(alignment), spacing: spacing ?? defaults.metric(1)
        ) {
          children
        })
    case .weighted(let properties, let vertical):
      return AnyView(
        NativeWeightedStack(
          node: node, properties: properties, vertical: vertical, activate: activate))
    case .overlay(let alignment):
      return AnyView(
        NativeNodeView(node: node.children[0], activate: activate)
          .overlay(alignment: nativeAlignment(alignment)) {
            NativeNodeView(node: node.children[1], activate: activate)
          })
    case .stack(let alignment):
      return AnyView(ZStack(alignment: nativeAlignment(alignment)) { children })
    case .layoutPriority(let value):
      return AnyView(child.layoutPriority(value))
    case .offset(let x, let y):
      return AnyView(child.offset(x: CGFloat(x), y: CGFloat(y)))
    case .text(let text):
      return AnyView(NativeTextView(text: text))
    case .richText(let spans):
      return AnyView(NativeRichTextView(spans: spans))
    case .image(let properties):
      guard let resource = node.imageResource else { preconditionFailure("Missing image resource") }
      return AnyView(NativeImageView(properties: properties, resource: resource))
    case .symbol(let symbol):
      return AnyView(NativeSymbolView(symbol: symbol))
    case .frame(let frame):
      return AnyView(child.modifier(NativeFrameModifier(frame: frame)))
    case .padding(let leading, let top, let trailing, let bottom):
      return AnyView(
        child.padding(
          EdgeInsets(
            top: CGFloat(top), leading: CGFloat(leading),
            bottom: CGFloat(bottom), trailing: CGFloat(trailing))))
    case .background(let color, let radius):
      return AnyView(
        child.background(
          Color(argb: color),
          in: RoundedRectangle(cornerRadius: CGFloat(radius), style: .continuous)))
    case .clip(let radius, let antialiased):
      return AnyView(
        child.clipShape(
          RoundedRectangle(cornerRadius: CGFloat(radius), style: .continuous),
          style: FillStyle(antialiased: antialiased)))
    case .animatedOpacity:
      guard let controller = node.opacityController else {
        preconditionFailure("Missing opacity controller")
      }
      return AnyView(NativeAnimatedOpacity(node: node, controller: controller, activate: activate))
    case .projection(let projection):
      return AnyView(child.projectionEffect(projection.native))
    case .opacity(let value):
      return AnyView(child.opacity(value))
    case .spacer(let minLength):
      return AnyView(Spacer(minLength: minLength.map { CGFloat($0) }))
    case .environment(let values):
      return AnyView(child.modifier(SwiftUIEnvironmentModifier(values: values)))
    case .slider(let properties):
      return AnyView(
        NativeSlider(node: node, controller: node.sliderController!, properties: properties))
    case .civilPicker(let properties):
      return AnyView(
        NativeCivilPicker(
          node: node, properties: properties, controller: node.civilPickerController!))
    case .table(let properties):
      return AnyView(
        NativeTable(
          node: node, children: node.children, properties: properties,
          controller: node.tableController!, activate: activate)
      )
    case .menu(let properties):
      return AnyView(
        NativeMenu(
          node: node, properties: properties, controller: node.menuController!, activate: activate))
    case .picker(let properties):
      return AnyView(
        NativePicker(
          node: node, properties: properties, controller: node.pickerController!, activate: activate
        ))
    case .booleanControl(let properties):
      return AnyView(
        NativeBooleanControl(
          node: node, controller: node.booleanControlController!, properties: properties,
          activate: activate
        ))
    case .controlSize(let size):
      let sizes: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
      return AnyView(child.controlSize(sizes[size]))
    case .button(let enabled, let role, let style, let autofocus):
      let button = Button(role: role == 1 ? .cancel : role == 2 ? .destructive : nil) {
        activate(node)
      } label: {
        child.modifier(NativeInteractiveBounds(icon: node.children.first?.containsSymbol == true))
      }
      let styled: AnyView
      switch style {
      case 1: styled = AnyView(button.buttonStyle(.plain))
      case 2: styled = AnyView(button.buttonStyle(.bordered))
      case 3: styled = AnyView(button.buttonStyle(.borderedProminent))
      default: styled = AnyView(button.buttonStyle(.automatic))
      }
      return AnyView(
        styled.modifier(
          NativeButtonFocus(
            controller: node.focusController!, autofocus: autofocus, activate: { activate(node) }
          )
        ).disabled(!enabled))
    }
  }
}

extension RenderNodeState {
  var containsSymbol: Bool {
    if case .symbol = properties { return true }
    return children.contains { $0.containsSymbol }
  }
}
