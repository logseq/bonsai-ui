import Foundation
import Observation

struct PresentationTicket: Equatable, Sendable {
  let session: UUID
  let epoch: UInt64
  let presentation: UInt64
  let revision: UInt64
}

@MainActor @Observable
final class BonsaiSession {
  let tree: RenderTree
  private(set) var application: ApplicationMetadata?
  private(set) var ticket: PresentationTicket?
  private(set) var displayedRevision: UInt64 = 0
  @ObservationIgnored private var deferredApplicationRequests: [ApplicationRequest] = []
  @ObservationIgnored private let applicationConnection: ApplicationBridgeConnection
  var isVisible = false { didSet { updateAnimationActivity() } }
  var isActive = true { didSet { updateAnimationActivity() } }

  private func updateAnimationActivity() {
    windowHost.dialogs.setActive(isVisible && isActive)
    windowHost.notices.setActive(isVisible && isActive && !windowHost.dialogs.blocksBackgroundInput)
    for node in tree.nodes.values {
      node.collectionController?.viewport.setAnimationsActive(isVisible && isActive)
      node.morphingSurfaceController?.setAnimationsActive(isVisible && isActive)
      node.progressAnimationsActive = isVisible && isActive
    }
    updateOpacityPresentation()
    updatePresentations()
    updateFieldFocus()
    updateHoverPresentation()
    updateFocusAndGesturePresentation()
    updateNativeViewPresentation()
    updateScrollPresentation()
    dispatchCommittedHostCommands()
    dispatchCommittedApplicationRequests()
  }

  private func updateNativeViewPresentation() {
    // Parent ownership must be established before any nested extension is enabled.
    var pending = tree.root.map { [$0] } ?? []
    while let node = pending.popLast() {
      pending.append(contentsOf: node.children.reversed())
      guard let instance = node.nativeView else { continue }
      let mounted = displayed.tree.nodes[node.id.node]
      instance.setPresented(
        isVisible && isActive && displayedRevision > 0
          && displayed.tree.epoch == node.id.epoch && mounted?.properties == node.properties
          && mounted?.bindings == node.bindings
          && mounted?.children == node.children.map { $0.id.node }
          && isInActiveContent(node, controlsOwnInput: false))
    }
  }

  private func updateScrollPresentation() {
    for node in tree.nodes.values {
      if let removal = node.removalController {
        let mounted = displayed.tree.nodes[node.id.node]
        removal.setPresentation(
          presented: displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
            && mounted?.properties == node.properties && mounted?.bindings == node.bindings,
          active: isVisible && isActive && isInActiveContent(node, controlsOwnInput: false))
      }
      if let refresh = node.refreshController {
        let mounted = displayed.tree.nodes[node.id.node]
        let active = isVisible && isActive && isInActiveContent(node, controlsOwnInput: false)
        refresh.setPresentation(
          presented: displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
            && mounted?.properties == node.properties && mounted?.bindings == node.bindings,
          active: active)
      }
      node.scrollCommand?.setActive(
        isVisible && isActive && isInActiveContent(node, controlsOwnInput: false))
      guard let observer = node.scrollObserver else { continue }
      let mounted = displayed.tree.nodes[node.id.node]
      observer.setPresented(
        isVisible && isActive && displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
          && mounted?.properties == node.properties && mounted?.bindings == node.bindings
          && node.bindings[EventTagId.scrollNotification] != nil
          && isInActiveContent(node, controlsOwnInput: false))
    }
  }

  private func updateFocusAndGesturePresentation() {
    for node in tree.nodes.values {
      let mounted = displayed.tree.nodes[node.id.node]
      node.keyboardController?.focus.setPresented(
        isVisible && isActive && displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
          && mounted?.properties == node.properties && mounted?.bindings == node.bindings
          && mounted?.children == node.children.map { $0.id.node }
          && isInActiveContent(node, controlsOwnInput: false))
      node.focusController?.setPresented(
        isVisible && isActive && displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
          && mounted?.properties == node.properties && mounted?.bindings == node.bindings
          && mounted?.children == node.children.map { $0.id.node }
          && isInActiveContent(node, controlsOwnInput: false))
      node.gestureController?.setPresented(
        isVisible && isActive && displayedRevision > 0 && displayed.tree.epoch == node.id.epoch
          && mounted?.properties == node.properties && mounted?.bindings == node.bindings
          && mounted?.children == node.children.map { $0.id.node }
          && isInActiveContent(node, controlsOwnInput: false))
    }
  }

  private func updateHoverPresentation() {
    if !isVisible || !isActive { tree.discardHoverInput() }
    for node in tree.nodes.values {
      node.hoverController?.setCollecting(
        isVisible && isActive && isInActiveContent(node, controlsOwnInput: false))
    }
    tree.hoverRouter.setPresented(
      isVisible && isActive && ticket == nil && pending == nil
        && displayedRevision > 0 && tree.revision == displayedRevision)
  }

  private func updateOpacityPresentation() {
    for node in tree.nodes.values {
      guard let controller = node.opacityController else { continue }
      let mounted = displayed.tree.nodes[node.id.node]
      controller.setPresentationActive(
        isVisible && isActive && displayedRevision > 0
          && displayed.tree.epoch == node.id.epoch && mounted?.properties == node.properties
          && mounted?.bindings == node.bindings && isInActiveContent(node, controlsOwnInput: false))
    }
  }

  private func updatePresentations() {
    for node in tree.presentationNodes {
      guard let controller = node.presentationController, let current = node.properties.presentation
      else { continue }
      let mounted = displayed.tree.nodes[node.id.node]
      var matching = false
      if let mounted, let previous = mounted.properties.presentation {
        matching =
          previous == current && mounted.bindings == node.bindings
          && mounted.children == node.children.map { $0.id.node }
      }
      controller.setPresentationActive(
        isVisible && isActive && displayedRevision > 0
          && displayed.tree.epoch == node.id.epoch && matching
          && isInActiveContent(node, ignoringModalBlocking: true))
    }
  }

  private func updateFieldFocus() {
    for node in tree.nodes.values.sorted(by: { $0.id.node < $1.id.node }) {
      guard let controller = node.fieldController else { continue }
      let active =
        isVisible && isActive && displayedRevision > 0
        && displayed.tree.epoch == node.id.epoch
        && displayed.tree.nodes[node.id.node]?.properties == node.properties
        && isInActiveContent(node)
      controller.setPresentationActive(active)
    }
  }

  @ObservationIgnored private var runtime: NativeRuntime?
  @ObservationIgnored private var opening: Task<NativeRuntime, any Error>?
  @ObservationIgnored private var sessionID = UUID()
  var lifetimeIdentity: UUID { sessionID }
  @ObservationIgnored private var closing = false
  @ObservationIgnored private var busy = false
  @ObservationIgnored private var pending: NativeOutput?
  @ObservationIgnored private var candidate = FrameState()
  @ObservationIgnored private var displayed = FrameState()
  @ObservationIgnored private var events = NativeEventQueue()
  @ObservationIgnored private var inputFailure: (any Error)?
  @ObservationIgnored private var sequence: UInt64 = 0
  @ObservationIgnored private var environmentSource: UUID?
  @ObservationIgnored private var observedEnvironment: NativeHostEnvironment?
  @ObservationIgnored private var sentEnvironment: NativeHostEnvironment?

  func beginEnvironmentObservation(source: UUID, sample: NativeHostEnvironment) {
    environmentSource = source
    observedEnvironment = nil
    observeEnvironment(sample, source: source)
  }

  func observeEnvironment(_ sample: NativeHostEnvironment, source: UUID) {
    guard source == environmentSource else { return }
    var writer = WireWriter()
    guard (try? sample.encode(into: &writer)) != nil else { return }
    observedEnvironment = sample
  }

  func endEnvironmentObservation(source: UUID) {
    guard environmentSource == source else { return }
    environmentSource = nil
    observedEnvironment = nil
  }

  private func publishEnvironment() {
    guard displayedRevision > 0, let sample = observedEnvironment,
      sample != sentEnvironment, enqueueApplication(.environmentChanged(sample))
    else { return }
    sentEnvironment = sample
  }

  private var now: Int64 { Int64(clamping: DispatchTime.now().uptimeNanoseconds) }

  @ObservationIgnored private let hostEffects: HostEffectDispatcher
  @ObservationIgnored let windowHost: NativeWindowHost
  @ObservationIgnored private var deferredHostCommands: [HostCommand] = []
  @ObservationIgnored private let announce: @MainActor (String) -> Void

  init(
    nativeViews: BonsaiNativeViews = BonsaiNativeViews(),
    announce: @escaping @MainActor (String) -> Void = postAccessibilityAnnouncement,
    hostService: (any HostService)? = nil,
    windowHost: NativeWindowHost? = nil,
    applicationBridge: BonsaiApplicationBridge? = nil
  ) {
    applicationConnection = ApplicationBridgeConnection(bridge: applicationBridge)
    let windowHost = windowHost ?? NativeWindowHost()
    tree = RenderTree(nativeViews: nativeViews)
    self.announce = announce
    self.windowHost = windowHost
    hostEffects = HostEffectDispatcher(
      service: hostService ?? NativeHostService(windowHost: windowHost))
    tree.onInput = { [weak self] node, payload in self?.input(node, payload: payload) ?? false }
    tree.onInteractionPermission = { [weak self] node in
      guard let self, self.isVisible, self.isActive, self.displayedRevision > 0,
        self.displayed.tree.epoch == node.id.epoch, self.tree.nodes[node.id.node] === node,
        let mounted = self.displayed.tree.nodes[node.id.node],
        mounted.properties == node.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node })
      else { return false }
      return self.isInActiveContent(node)
    }
    windowHost.allowsFeedback = { [weak self] in
      guard let self else { return false }
      return self.runtime != nil && !self.closing && self.isActive && self.isVisible
        && self.displayedRevision > 0
    }
    windowHost.hasModalContent = { [weak self] in
      guard let self else { return false }
      return self.tree.nativeViewNodes.contains { $0.nativeView?.blocksBackgroundInput == true }
        || self.tree.presentationNodes.contains {
          $0.properties.presentation?.isModal == true
            && $0.presentationController?.presented == true
        }
    }
    windowHost.dialogs.onModalChange = { [weak self] in
      guard let self else { return }
      self.windowHost.notices.setActive(
        self.isVisible && self.isActive && !self.windowHost.dialogs.blocksBackgroundInput)
      self.updatePresentations()
      self.updateFieldFocus()
      self.updateHoverPresentation()
      self.updateFocusAndGesturePresentation()
      self.updateNativeViewPresentation()
      self.updateScrollPresentation()
    }
    tree.onInputFailure = { [weak self] error in self?.inputFailure = error }
    windowHost.resolveNode = { [weak self] id, controlsOwnInput in
      guard let self, isVisible, isActive, displayedRevision > 0,
        let node = tree.nodes[id], displayed.tree.epoch == node.id.epoch,
        let mounted = displayed.tree.nodes[id], mounted.properties == node.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node }),
        isInActiveContent(node, controlsOwnInput: controlsOwnInput)
      else { return nil }
      return node
    }
  }

  func start(
    entrypoint: String, payload: Data = Data(), lifetimeIdentity identity: UUID = UUID()
  ) async throws {
    guard runtime == nil, opening == nil, !closing else { throw NativeRuntimeError.startupFailed }
    sessionID = identity
    let task = Task { try await NativeRuntime.open(entrypoint: entrypoint, payload: payload) }
    opening = task
    do {
      let ownedRuntime = try await task.value
      guard sessionID == identity, !Task.isCancelled else {
        await ownedRuntime.close()
        throw CancellationError()
      }
      opening = nil
      runtime = ownedRuntime
      try await refresh()
    } catch {
      if sessionID == identity { opening = nil }
      throw error
    }
  }

  @discardableResult func refresh() async throws -> Bool {
    updateOpacityPresentation()
    updatePresentations()
    updateFieldFocus()
    updateHoverPresentation()
    updateFocusAndGesturePresentation()
    updateNativeViewPresentation()
    updateScrollPresentation()
    if let inputFailure { throw inputFailure }
    guard let runtime, isVisible, isActive, !busy, pending == nil else { return false }
    let identity = sessionID
    busy = true
    defer { if sessionID == identity { busy = false } }
    sampleCollectionRequests()
    publishEnvironment()
    dispatchCommittedApplicationRequests()
    // A reply can complete while a newer frame awaits presentation. Runtime
    // controls must name the revision current when the next pump begins.
    let batchEvents = events.pumpEvents.map { event in
      if event.payload.isRuntimeControl {
        return NativeEvent(
          sequence: event.sequence, displayedRevision: displayedRevision,
          nodeID: 0, handlerID: 0, payload: event.payload)
      }
      return event
    }
    let batch =
      batchEvents.isEmpty
      ? Data() : try EventBatch.encode(epoch: displayed.tree.epoch, events: batchEvents)
    let swipeRequests = batchEvents.compactMap {
      event -> (SwipeActionsController, SwipeActionsController.Request)? in
      guard case .press = event.payload, let owner = tree.nodes[event.nodeID]?.swipeActionOwner,
        let request = owner.pending
      else { return nil }
      return (owner, request)
    }
    let sliderRequests = batchEvents.compactMap {
      event -> (SliderController, SliderController.Request)? in
      guard event.payload.sliderSelection != nil,
        let controller = tree.nodes[event.nodeID]?.sliderController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let civilRequests = batchEvents.compactMap {
      event -> (CivilPickerController, CivilPickerController.Request)? in
      guard event.payload.civilSelection != nil,
        let controller = tree.nodes[event.nodeID]?.civilPickerController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let tableRequests = batchEvents.compactMap {
      event -> (NativeTableController, NativeTableController.Request)? in
      guard
        [EventTagId.tableSortRequested, EventTagId.tableRowSelected].contains(event.payload.tag),
        let controller = tree.nodes[event.nodeID]?.tableController,
        let request = controller.pending.last
      else { return nil }
      return (controller, request)
    }
    let menuRequests = batchEvents.compactMap {
      event -> (NativeMenuController, NativeMenuController.Request)? in
      guard case .menuAction = event.payload,
        let controller = tree.nodes[event.nodeID]?.menuController,
        let request = controller.pending.last
      else { return nil }
      return (controller, request)
    }
    let scrollRequests = batchEvents.compactMap {
      event -> (ScrollTargetsController, ScrollTargetsController.Request)? in
      guard case .scrollPosition = event.payload,
        let controller = tree.nodes[event.nodeID]?.scrollTargetsController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let pickerRequests = batchEvents.compactMap {
      event -> (PickerController, PickerController.Request)? in
      guard case .pickerSelection = event.payload,
        let controller = tree.nodes[event.nodeID]?.pickerController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let presentationRequests = batchEvents.compactMap {
      event -> (PresentationController, PresentationController.Request)? in
      guard case .valueChanged = event.payload,
        let controller = tree.nodes[event.nodeID]?.presentationController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let booleanRequests = batchEvents.compactMap {
      event -> (BooleanControlController, BooleanControlController.Request)? in
      guard case .valueChanged = event.payload,
        let controller = tree.nodes[event.nodeID]?.booleanControlController,
        let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let tabRequests = batchEvents.compactMap {
      event -> (TabsController, TabsController.Request)? in
      guard case .tabSelection = event.payload,
        let controller = tree.nodes[event.nodeID]?.tabsController, let request = controller.pending
      else { return nil }
      return (controller, request)
    }
    let splitRequests = batchEvents.compactMap {
      event -> (NavigationSplitController, RenderSplitState)? in
      guard case .navigationSplit(let state) = event.payload,
        let controller = tree.nodes[event.nodeID]?.splitController
      else { return nil }
      return (controller, state)
    }
    let navigationRequests = batchEvents.compactMap { event -> RenderNodeState? in
      guard case .navigationPath = event.payload else { return nil }
      return tree.nodes[event.nodeID]
    }
    events.removePrefix(batchEvents.count)
    let output = try await runtime.pump(monotonicNanoseconds: now, events: batch)
    guard sessionID == identity else { return false }
    defer {
      for (controller, request) in swipeRequests { controller.resolve(request) }
      for node in navigationRequests { node.navigationController?.resolve() }
      for (controller, state) in splitRequests { controller.resolve(state) }
      for (controller, request) in sliderRequests { controller.resolve(request) }
      for (controller, request) in booleanRequests { controller.resolve(request) }
      for (controller, request) in presentationRequests { controller.resolve(request) }
      for (controller, request) in civilRequests { controller.resolve(request) }
      for (controller, request) in tableRequests { controller.resolve(request) }
      for (controller, request) in menuRequests { controller.resolve(request) }
      for (controller, request) in scrollRequests { controller.resolve(request) }
      for (controller, request) in pickerRequests { controller.resolve(request) }
      for (controller, request) in tabRequests { controller.resolve(request) }
    }
    guard output.status != 2 else {
      throw NativeRuntimeError.nativeFailure(status: output.status, code: output.errorCode)
    }
    if output.bytes.isEmpty {
      guard displayedRevision > 0, output.revision == displayedRevision else {
        try await runtime.reject(output)
        throw NativeRuntimeError.malformedOutput
      }
      // The already-presented tree did not change. This token still closes
      // the native transaction but needs no second layout acknowledgment.
      try await runtime.acknowledge(output, monotonicNanoseconds: now)
      return false
    }
    let next: FrameState
    do {
      let frame = try WireFrame.decode(output.bytes)
      guard frame.revision == output.revision else { throw NativeRuntimeError.malformedOutput }
      next = try displayed.staging(frame)
      try tree.validate(next.tree)
    } catch {
      try await runtime.reject(output)
      throw error
    }
    guard sessionID == identity else { return false }
    candidate = next
    tree.hoverRouter.setPresented(false)
    tree.commit(next.tree)
    updateAnimationActivity()
    application = next.application
    pending = output
    ticket = PresentationTicket(
      session: identity, epoch: next.tree.epoch,
      presentation: output.presentationID, revision: output.revision)
    return true
  }

  @discardableResult func presented(_ observed: PresentationTicket) async throws -> Bool {
    guard let runtime, let output = pending, ticket == observed,
      isVisible, isActive, !busy
    else { return false }
    let identity = sessionID
    busy = true
    defer { if sessionID == identity { busy = false } }
    try await runtime.acknowledge(output, monotonicNanoseconds: now)
    guard sessionID == identity, ticket == observed else { return false }
    let announcements = candidate.tree.liveAnnouncements(since: displayed.tree)
    displayed = candidate
    displayedRevision = observed.revision
    deferredHostCommands.append(contentsOf: candidate.hostCommands)
    deferredApplicationRequests.append(contentsOf: candidate.applicationRequests)
    pending = nil
    ticket = nil
    updateOpacityPresentation()
    updatePresentations()
    updateFieldFocus()
    updateHoverPresentation()
    updateFocusAndGesturePresentation()
    updateNativeViewPresentation()
    updateScrollPresentation()
    if isVisible && isActive { for text in announcements { announce(text) } }
    dispatchCommittedHostCommands()
    dispatchCommittedApplicationRequests()
    return true
  }

  @discardableResult func activate(_ node: RenderNodeState) -> Bool {
    guard isVisible, isActive, displayed.tree.epoch == node.id.epoch,
      tree.nodes[node.id.node] === node,
      let mounted = displayed.tree.nodes[node.id.node],
      let handler = mounted.bindings[EventTagId.press]
    else { return false }
    switch mounted.properties {
    case .button(enabled: true, role: _, style: _, autofocus: _): break
    case .swipeAction(let properties):
      guard properties.enabled, node.properties == mounted.properties,
        node.bindings == mounted.bindings,
        let owner = node.swipeActionOwner, owner.dispatching == node.id,
        let currentParent = tree.nodes[owner.identity.node],
        let previousParent = displayed.tree.nodes[owner.identity.node],
        previousParent.properties == currentParent.properties,
        previousParent.children == currentParent.children.map({ $0.id.node })
      else { return false }
    default: return false
    }
    return enqueue(node, handler: handler, payload: .press)
  }

  private func sampleCollectionRequests() {
    for node in tree.nodes.values.sorted(by: { $0.id.node < $1.id.node }) {
      guard node.id.epoch == displayed.tree.epoch,
        let controller = node.collectionController,
        let mounted = displayed.tree.nodes[node.id.node],
        case .collection = mounted.properties,
        let handler = mounted.bindings[EventTagId.visibleRangeChanged],
        let range = controller.request(handler: handler)
      else { continue }
      if enqueue(node, handler: handler, payload: .visibleRange(range)) {
        controller.accepted(range, handler: handler)
      }
    }
  }

  private func input(_ node: RenderNodeState, payload: NativeEventPayload) -> Bool {
    if case .key = payload {
      guard inputFailure == nil, isVisible, isActive, displayedRevision > 0,
        displayed.tree.epoch == node.id.epoch, tree.nodes[node.id.node] === node,
        node.keyboardController?.isCollecting == true,
        let mounted = displayed.tree.nodes[node.id.node], mounted.properties == node.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag],
        isInActiveContent(node, controlsOwnInput: false)
      else { return false }
      let accepted = enqueue(node, handler: handler, payload: payload)
      if !accepted { inputFailure = WireError.limitExceeded }
      return accepted
    }
    if case .focusChanged = payload, let controller = node.focusController {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, controller.isCollecting,
        let mounted = displayed.tree.nodes[node.id.node], mounted.properties == node.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag],
        isInActiveContent(node, controlsOwnInput: false)
      else { return false }
      let accepted = enqueue(node, handler: handler, payload: payload)
      if !accepted { inputFailure = WireError.limitExceeded }
      return accepted
    }
    if case .nativeView(let event) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let instance = node.nativeView,
        instance.id == event.instance, instance.accepts(event.generation),
        instance.prepared.envelope.kind == event.kind,
        instance.prepared.envelope.version == event.version,
        let mounted = displayed.tree.nodes[node.id.node], mounted.properties == node.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[EventTagId.nativeEvent], isInActiveContent(node)
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if payload.isGenericGesture {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, node.gestureController?.isCollecting == true,
        let mounted = displayed.tree.nodes[node.id.node], case .gesture = mounted.properties,
        mounted.bindings == node.bindings, mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag],
        isInActiveContent(node, controlsOwnInput: false)
      else { return false }
      let accepted = enqueue(node, handler: handler, payload: payload)
      if !accepted { inputFailure = WireError.limitExceeded }
      return accepted
    }
    if let pointer = payload.hoverPointer {
      guard pointer.isValid, isVisible, isActive, ticket == nil, pending == nil,
        displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node,
        let mounted = displayed.tree.nodes[node.id.node],
        case .hoverRegion = mounted.properties, mounted.properties == node.properties,
        mounted.bindings == node.bindings,
        let handler = mounted.bindings[payload.tag]
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .scroll(let pixels, let delta) = payload {
      guard inputFailure == nil, pixels.isFinite, delta.isFinite, isVisible, isActive,
        displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, node.scrollObserver?.isCollecting == true,
        let mounted = displayed.tree.nodes[node.id.node], mounted.properties == node.properties,
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler,
        isInActiveContent(node, controlsOwnInput: false)
      else { return false }
      let accepted = enqueue(node, handler: handler, payload: payload)
      if !accepted { inputFailure = WireError.limitExceeded }
      return accepted
    }
    if case .press = payload { return activate(node) }
    if case .animationCompleted(let id) = payload {
      guard isVisible, isActive, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        mounted.properties == node.properties, node.opacityController?.canComplete(id) == true,
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if let selection = payload.sliderSelection {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .slider(let previous) = mounted.properties,
        case .slider(let current) = node.properties,
        previous.enabled, current.enabled, previous.sameConfiguration(as: current),
        current.contains(selection),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if let selection = payload.civilSelection {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .civilPicker(let previous) = mounted.properties,
        case .civilPicker(let current) = node.properties,
        previous.sameConfiguration(as: current), current.admits(selection),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if payload.tag == EventTagId.removalRequested || payload.tag == EventTagId.removalCompleted {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, isInActiveContent(node, controlsOwnInput: false),
        let mounted = displayed.tree.nodes[node.id.node],
        case .removal(let previous) = mounted.properties,
        case .removal(let current) = node.properties, previous == current,
        let controller = node.removalController,
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      switch payload {
      case .removalRequested(let token, let direction):
        guard controller.dispatching, token == current.token,
          current.state == 0 || current.state == 3,
          current.vertical ? (2...3).contains(direction) : (0...1).contains(direction)
        else { return false }
      case .removalCompleted(let token): guard controller.canComplete(token) else { return false }
      default: return false
      }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .refreshRequest(let token) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, isInActiveContent(node, controlsOwnInput: false),
        let mounted = displayed.tree.nodes[node.id.node],
        case .refresh(let previous) = mounted.properties,
        case .refresh(let current) = node.properties,
        previous == current, current.token == token, current.state == 0,
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .scrollPosition(let id) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .scrollTargets(let previous) = mounted.properties,
        case .scrollTargets(let current) = node.properties,
        previous.sameConfiguration(as: current), current.admits(id),
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if [EventTagId.tableSortRequested, EventTagId.tableRowSelected].contains(payload.tag) {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .table(let previous) = mounted.properties, case .table(let current) = node.properties,
        previous.sameConfiguration(as: current), current.admits(payload),
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .menuAction(let id) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .menu(let previous) = mounted.properties, case .menu(let current) = node.properties,
        previous.sameConfiguration(as: current), current.admits(id),
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .pickerSelection(let selected) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .picker(let previous) = mounted.properties,
        case .picker(let current) = node.properties,
        previous.sameConfiguration(as: current), current.admits(selected),
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .valueChanged(let requested) = payload, let current = node.properties.presentation {
      guard !requested, isVisible, isActive, displayedRevision > 0,
        displayed.tree.epoch == node.id.epoch, tree.nodes[node.id.node] === node,
        let mounted = displayed.tree.nodes[node.id.node],
        let previous = mounted.properties.presentation,
        previous == current, current.presented, current.allowsDismissal,
        node.presentationController?.active == true,
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .valueChanged = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .booleanControl(let previous) = mounted.properties,
        case .booleanControl(let current) = node.properties,
        previous.enabled, current.enabled, previous.style == current.style,
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    // Native navigation controls can finish a transition while its prior echo
    // awaits presentation. Fence semantic ownership, not the echoed selection/
    // column values, and retain the actual displayed revision on the queued event.
    if case .tabSelection(let requested) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .tabs = mounted.properties, case .tabs = node.properties,
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      var found = false
      for child in node.children {
        guard displayed.tree.nodes[child.id.node]?.properties == child.properties,
          case .tab(let tab) = child.properties
        else { return false }
        if tab.key == requested { found = true }
      }
      return found && enqueue(node, handler: handler, payload: payload)
    }
    if case .navigationSplit(let requested) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .navigationSplit(let previous) = mounted.properties,
        case .navigationSplit(let current) = node.properties,
        previous.state.selectionIdentity == current.state.selectionIdentity,
        previous.sidebarTitle == current.sidebarTitle,
        previous.contentTitle == current.contentTitle,
        previous.detailTitle == current.detailTitle,
        mounted.children == node.children.map({ $0.id.node }),
        requested.isValid, current.contentTitle != nil || requested.compactColumn != 1,
        requested.selectionIdentity == current.state.selectionIdentity,
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .navigationPath(let keys) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, let mounted = displayed.tree.nodes[node.id.node],
        case .navigationStack = mounted.properties, case .navigationStack = node.properties,
        mounted.children == node.children.map({ $0.id.node }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler,
        keys.count < mounted.children.count - 1
      else { return false }
      for (index, child) in node.children.dropFirst().enumerated() {
        guard let previous = displayed.tree.nodes[child.id.node],
          previous.properties == child.properties,
          case .navigationDestination(let destination) = child.properties
        else { return false }
        if index < keys.count {
          guard Data(keys[index].utf8) == Data(destination.key.utf8) else { return false }
        } else if !destination.canPop {
          return false
        }
      }
      return enqueue(node, handler: handler, payload: payload)
    }
    if case .semanticsAction(let id) = payload {
      guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
        tree.nodes[node.id.node] === node, !node.accessibilityHidden,
        !displayed.tree.accessibilityHiddenNodes.contains(node.id.node),
        let mounted = displayed.tree.nodes[node.id.node],
        case .semantics(let previous) = mounted.properties,
        case .semantics(let current) = node.properties,
        previous.actions.contains(where: { $0.id == id }),
        current.actions.contains(where: { $0.id == id }),
        let handler = mounted.bindings[payload.tag], node.bindings[payload.tag] == handler
      else { return false }
      return enqueue(node, handler: handler, payload: payload)
    }
    guard isVisible, isActive, displayedRevision > 0, displayed.tree.epoch == node.id.epoch,
      tree.nodes[node.id.node] === node,
      let mounted = displayed.tree.nodes[node.id.node],
      let displayedEditor = mounted.properties.textEditing,
      let currentEditor = node.properties.textEditing,
      displayedEditor.snapshot.sessionID == currentEditor.snapshot.sessionID,
      let handler = mounted.bindings[payload.tag]
    else { return false }
    switch payload {
    case .environmentChanged, .key, .tap, .doubleTap, .longPress, .nativeView, .tableSort,
      .tableSelection, .scroll,
      .hostResponse, .applicationResponse, .applicationRequestError, .applicationEvent,
      .animationCompleted,
      .civilDate,
      .civilTime, .menuAction,
      .scrollPosition, .refreshRequest, .removalRequested, .removalCompleted:
      return false
    case .textEdit(let edit):
      guard displayedEditor.configuration.enabled, currentEditor.configuration.enabled,
        edit.sessionID == currentEditor.snapshot.sessionID
      else { return false }
    case .textSubmit:
      guard displayedEditor.configuration.enabled, currentEditor.configuration.enabled,
        !displayedEditor.configuration.readOnly, !currentEditor.configuration.readOnly
      else { return false }
    case .focusChanged(let focused):
      if focused && !currentEditor.configuration.enabled { return false }
    case .textLimitReached: break
    case .sliderChanged, .sliderEnded, .rangeSliderChanged, .rangeSliderEnded, .valueChanged,
      .press, .visibleRange, .semanticsAction, .navigationPath, .navigationSplit,
      .tabSelection, .pickerSelection, .pointerEnter, .pointerLeave, .pointerDown, .pointerUp:
      return false
    }
    return enqueue(node, handler: handler, payload: payload)
  }

  private func isInActiveContent(
    _ node: RenderNodeState, controlsOwnInput: Bool = true,
    ignoringModalBlocking: Bool = false
  ) -> Bool {
    guard !windowHost.dialogs.blocksBackgroundInput else { return false }
    if !ignoringModalBlocking {
      for owner in tree.nativeViewNodes where owner.nativeView?.blocksBackgroundInput == true {
        var candidate: UInt64? = node.id.node
        while let id = candidate, id != owner.id.node { candidate = tree.parents[id] }
        if candidate == nil { return false }
      }
      for owner in tree.presentationNodes where owner !== node {
        guard owner.properties.presentation?.isModal == true,
          owner.presentationController?.active == true,
          owner.presentationController?.presented == true,
          owner.presentationController?.nativeVisible == true, let content = owner.children.last
        else { continue }
        var candidate: UInt64? = node.id.node
        while let id = candidate, id != content.id.node { candidate = tree.parents[id] }
        if candidate == nil { return false }
      }
    }

    var child = node
    while let parentID = tree.parents[child.id.node], let parent = tree.nodes[parentID] {
      if let instance = parent.nativeView {
        guard instance.containsMountedChild(child.id),
          let mounted = displayed.tree.nodes[parentID], mounted.properties == parent.properties,
          mounted.bindings == parent.bindings,
          mounted.children == parent.children.map({ $0.id.node })
        else { return false }
      }
      if controlsOwnInput, case .swipeAction = parent.properties { return false }
      if let current = parent.properties.presentation, current.isModal,
        current.presented, parent.children.first === child
      {
        return false
      }
      if let current = parent.properties.presentation, parent.children.last === child {
        guard let mounted = displayed.tree.nodes[parentID],
          let previous = mounted.properties.presentation,
          previous == current, current.presented, parent.presentationController?.presented == true,
          parent.presentationController?.active == true,
          parent.presentationController?.nativeVisible == true,
          mounted.children == parent.children.map({ $0.id.node })
        else { return false }
      }
      if case .booleanControl(let current) = parent.properties {
        switch current.style {
        case .toggle:
          if controlsOwnInput { return false }
        case .disclosure:
          if parent.children.first === child {
            if controlsOwnInput { return false }
          } else {
            guard let mounted = displayed.tree.nodes[parentID],
              case .booleanControl(let previous) = mounted.properties,
              previous.style == .disclosure, previous.value, current.value,
              parent.booleanControlController?.value == true,
              !controlsOwnInput || (previous.enabled && current.enabled),
              mounted.children == parent.children.map({ $0.id.node })
            else { return false }
          }
        }
      }
      switch parent.properties {
      case .scrollSections, .scrollSection:
        guard let mounted = displayed.tree.nodes[parentID],
          mounted.properties == parent.properties,
          mounted.children == parent.children.map({ $0.id.node })
        else { return false }
        if case .scrollSection(let section) = parent.properties {
          if parent.children[0] === child && !section.hasHeader { return false }
          if parent.children[1] === child && !section.hasFooter { return false }
        }
      default: break
      }
      if case .toolbar = parent.properties, parent.children.first !== child {
        guard let mounted = displayed.tree.nodes[parentID],
          mounted.properties == parent.properties,
          mounted.children == parent.children.map({ $0.id.node })
        else { return false }
      }
      if case .table(let properties) = parent.properties {
        guard let mounted = displayed.tree.nodes[parentID],
          case .table(let previous) = mounted.properties,
          previous.sameConfiguration(as: properties),
          mounted.children == parent.children.map({ $0.id.node }),
          let index = parent.children.firstIndex(where: { $0 === child })
        else { return false }
        if index < properties.columns.count {
          guard properties.columns[index].hasDetails,
            parent.tableController?.detailsExpanded == true
          else { return false }
        }
      }
      if parent.removalController?.blocksContent == true { return false }
      if controlsOwnInput, case .menu = parent.properties { return false }
      if controlsOwnInput, case .picker = parent.properties { return false }
      if controlsOwnInput, case .swipeActions = parent.properties, parent.children.first === child,
        parent.swipeController?.offset != 0
      {
        return false
      }
      if case .morphingSurface(let surface) = parent.properties {
        guard let previous = displayed.tree.nodes[parentID],
          case .morphingSurface(let displayedSurface) = previous.properties,
          displayedSurface.expanded == surface.expanded,
          previous.children == parent.children.map({ $0.id.node }),
          parent.children[surface.expanded ? 1 : 0] === child
        else { return false }
      }
      if case .tab(let tab) = child.properties {
        guard let previous = displayed.tree.nodes[parentID],
          case .tabs(let selection) = previous.properties,
          case .tabs(let current) = parent.properties, current == selection,
          selection == tab.key, parent.tabsController?.selection == tab.key,
          previous.children.contains(child.id.node),
          displayed.tree.nodes[child.id.node]?.properties == child.properties
        else { return false }
      }
      if let navigation = parent.navigationController {
        let visibleID = navigation.path.last?.node.node ?? parent.children.first?.id.node
        guard let previous = displayed.tree.nodes[parentID],
          case .navigationStack = previous.properties,
          previous.children == parent.children.map({ $0.id.node }),
          previous.children.last == visibleID, child.id.node == visibleID,
          displayed.tree.nodes[child.id.node]?.properties == child.properties
        else { return false }
      }
      child = parent
    }
    return true
  }

  private func enqueue(_ node: RenderNodeState, handler: UInt64, payload: NativeEventPayload)
    -> Bool
  {
    guard
      isInActiveContent(
        node,
        controlsOwnInput: payload.hoverPointer == nil
          && payload.tag != EventTagId.animationCompleted
          && payload.tag != EventTagId.scrollNotification),
      sequence < UInt64(Int64.max),
      events.append(
        NativeEvent(
          sequence: sequence + 1, displayedRevision: displayedRevision,
          nodeID: node.id.node, handlerID: handler, payload: payload))
    else { return false }
    sequence += 1
    if payload == .press { tree.swipeContentTapped(node) }
    return true
  }

  private func enqueueApplication(_ payload: NativeEventPayload) -> Bool {
    guard sequence < UInt64(Int64.max),
      events.append(
        NativeEvent(
          sequence: sequence + 1, displayedRevision: displayedRevision,
          nodeID: 0, handlerID: 0, payload: payload))
    else { return false }
    sequence += 1
    return true
  }

  private func dispatchCommittedApplicationRequests() {
    guard isVisible, isActive, runtime != nil, displayedRevision > 0 else { return }
    let identity = sessionID
    applicationConnection.connect(
      send: { [weak self] bytes in
        guard let self, self.sessionID == identity, self.runtime != nil else {
          throw BonsaiApplicationEvents.SendError.closed
        }
        guard self.enqueueApplication(.applicationEvent(bytes)) else {
          throw BonsaiApplicationEvents.SendError.backpressure
        }
      },
      deliver: { [weak self] payload in
        guard let self, self.sessionID == identity, self.runtime != nil,
          self.isVisible, self.isActive
        else { return false }
        return self.enqueueApplication(payload)
      })
    let requests = deferredApplicationRequests
    deferredApplicationRequests.removeAll()
    applicationConnection.dispatch(requests)
  }

  private func dispatchCommittedHostCommands() {
    guard isVisible, isActive, runtime != nil, !deferredHostCommands.isEmpty else { return }
    let commands = deferredHostCommands
    deferredHostCommands.removeAll()
    let identity = sessionID
    hostEffects.dispatch(commands) { [weak self] response in
      guard let self, self.sessionID == identity, self.runtime != nil else { return }
      guard self.sequence < UInt64(Int64.max),
        self.events.append(
          NativeEvent(
            sequence: self.sequence + 1, displayedRevision: self.displayedRevision,
            nodeID: 0, handlerID: 0, payload: .hostResponse(response)))
      else {
        self.inputFailure = WireError.limitExceeded
        return
      }
      self.sequence += 1
    }
  }

  func close(ifCurrent identity: UUID) async {
    guard sessionID == identity else { return }
    await close()
  }

  func close() async {
    let oldOpening = opening
    let oldRuntime = runtime
    let identity = UUID()
    sessionID = identity
    hostEffects.reset()
    applicationConnection.reset()
    deferredApplicationRequests.removeAll()
    windowHost.close()
    deferredHostCommands.removeAll()
    closing = true
    opening = nil
    runtime = nil
    pending = nil
    ticket = nil
    busy = false
    candidate = FrameState()
    displayed = FrameState()
    displayedRevision = 0
    sequence = 0
    environmentSource = nil
    observedEnvironment = nil
    sentEnvironment = nil
    events.removeAll()
    inputFailure = nil
    application = nil
    tree.discardHoverInput()
    tree.hoverRouter.reset()
    tree.commit(NodeStore())
    if let oldOpening, let owned = try? await oldOpening.value { await owned.close() }
    await oldRuntime?.close()
    if sessionID == identity { closing = false }
  }
}
