import SwiftUI

struct ListRowAddress: Hashable, Sendable {
  let section: Data
  let path: [Data]
}

struct RenderListScrollRequest: Equatable, Sendable {
  let token: Int64
  let target: ListRowAddress
  let anchor: Int
  let animated: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let token = Int64(bitPattern: try reader.integer(UInt64.self))
    guard token > 0 else { throw TreeError.invalidProperties }
    let section = try reader.listKey()
    let count = Int(try reader.integer(UInt16.self))
    guard (1...256).contains(count) else { throw TreeError.invalidProperties }
    var path: [Data] = []
    for _ in 0..<count { path.append(try reader.listKey()) }
    return Self(
      token: token, target: ListRowAddress(section: section, path: path),
      anchor: try reader.choice(2), animated: try reader.flag())
  }
}

struct RenderListProperties: Equatable, Sendable {
  let style: Int
  let request: RenderListScrollRequest?
  static func decode(_ reader: inout WireReader) throws -> Self {
    let style = try reader.choice(2)
    let request = try reader.flag() ? RenderListScrollRequest.decode(&reader) : nil
    return Self(style: style, request: request)
  }
}

extension WireReader {
  mutating func listKey() throws -> Data {
    let key = try string()
    guard !key.isEmpty else { throw TreeError.invalidProperties }
    return Data(key.utf8)
  }
}

struct ListScrollTarget: Equatable {
  let identity: RenderIdentity
  let visible: Bool
}

struct ListScrollGeometry {
  let row: CGRect
  let viewport: CGRect
  let minimumOffset: CGFloat
  let maximumOffset: CGFloat

  func aligned(anchor: Int) -> Bool {
    guard
      [row.minY, row.height, viewport.minY, viewport.height, minimumOffset, maximumOffset]
        .allSatisfy(\.isFinite), row.height > 0, viewport.height > 0,
      minimumOffset <= maximumOffset
    else { return false }
    let fraction = CGFloat(anchor) / 2
    let desired = min(
      maximumOffset,
      max(
        minimumOffset,
        row.minY + row.height * fraction - viewport.height * fraction))
    return abs(viewport.minY - desired) <= 1
  }
}

enum ListScrollOutcome: Int64, Sendable {
  case succeeded, missingTarget, hiddenTarget, cancelled, superseded, positioningFailed
}

struct ListScrollCompletion: Equatable, Sendable {
  let token: Int64
  let handler: UInt64
  let outcome: ListScrollOutcome
}

@MainActor final class ListScrollController {
  private struct Pending {
    let request: RenderListScrollRequest
    let handler: UInt64
    let target: RenderIdentity
    let created: Double
    var started: Double?
    var stable: (time: Double, geometry: ListScrollGeometry)?
  }
  private var pending: Pending?
  private var latest: Int64 = 0
  private var acknowledged: Int64 = 0
  private var completions: [ListScrollCompletion] = []
  private var owner: UUID?
  private var move: ((RenderIdentity, Int, Bool) -> Void)?
  private var geometry: ((RenderIdentity) -> ListScrollGeometry?)?
  private var stop: (() -> Void)?
  private var active = false
  private var ready = false
  private var disposed = false
  private var sampling: Task<Void, Never>?
  private let automaticallySample: Bool
  private let now: () -> Double
  private let emit: (ListScrollCompletion) -> Bool
  private(set) var delivering: ListScrollCompletion?
  let nativeHost = ListScrollNativeHost()
  var reducedMotion = false

  init(
    automaticallySample: Bool = true,
    now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
    emit: @escaping (ListScrollCompletion) -> Bool
  ) {
    self.automaticallySample = automaticallySample
    self.now = now
    self.emit = emit
  }

  func synchronize(
    _ request: RenderListScrollRequest?, handler: UInt64?,
    rows: [ListRowAddress: ListScrollTarget]
  ) {
    guard !disposed else { return }
    guard let request else {
      finish(.cancelled)
      return
    }
    if request.token > latest {
      finish(.superseded)
      latest = request.token
      ready = false
      guard let handler else { preconditionFailure("Validated request has no completion handler") }
      guard let target = rows[request.target], target.visible else {
        completions.append(
          .init(
            token: request.token, handler: handler,
            outcome: rows[request.target] == nil ? .missingTarget : .hiddenTarget))
        deliver()
        return
      }
      pending = Pending(request: request, handler: handler, target: target.identity, created: now())
      beginSampling()
    } else if let pending,
      rows[pending.request.target] != ListScrollTarget(identity: pending.target, visible: true)
    {
      finish(.cancelled)
    }
  }

  func setPresentation(active: Bool, ready: Bool, acknowledgedToken: Int64?) {
    guard !disposed else { return }
    self.active = active
    self.ready = ready
    if let acknowledgedToken { acknowledged = max(acknowledged, acknowledgedToken) }
    if !active { finish(.cancelled) }
    sample()
  }

  func attach(
    owner: UUID, move: @escaping (RenderIdentity, Int, Bool) -> Void,
    geometry: @escaping (RenderIdentity) -> ListScrollGeometry?, stop: @escaping () -> Void
  ) {
    guard !disposed else { return }
    if self.owner != nil && self.owner != owner { finish(.cancelled) }
    self.owner = owner
    self.move = move
    self.geometry = geometry
    self.stop = stop
    sample()
  }

  func detach(owner: UUID) {
    guard self.owner == owner else { return }
    finish(.cancelled)
    self.owner = nil
    move = nil
    geometry = nil
    stop = nil
  }

  func sample() {
    guard !disposed else { return }
    defer { deliver() }
    guard var current = pending else { return }
    let time = now()
    guard let started = current.started else {
      guard time - current.created < 0.5 else {
        finish(.positioningFailed)
        return
      }
      guard active, ready, owner != nil, let move else { return }
      current.started = time
      pending = current
      // Issuing the command must not depend on a lazy cell already being realized.
      move(current.target, current.request.anchor, current.request.animated && !reducedMotion)
      return
    }
    guard time - started < 2 else {
      finish(.positioningFailed)
      return
    }
    guard let observation = geometry?(current.target),
      observation.aligned(anchor: current.request.anchor)
    else {
      current.stable = nil
      pending = current
      return
    }
    if let stable = current.stable,
      abs(stable.geometry.viewport.minY - observation.viewport.minY) <= 1,
      abs(stable.geometry.row.minY - observation.row.minY) <= 1,
      abs(stable.geometry.row.height - observation.row.height) <= 1
    {
      if time - stable.time >= 0.016 { finish(.succeeded) }
    } else {
      current.stable = (time, observation)
      pending = current
    }
  }

  func userInteraction() { finish(.cancelled) }

  private func finish(_ outcome: ListScrollOutcome) {
    guard let current = pending else { return }
    pending = nil
    sampling?.cancel()
    sampling = nil
    if current.started != nil && outcome != .succeeded { stop?() }
    completions.append(
      .init(token: current.request.token, handler: current.handler, outcome: outcome))
    deliver()
  }

  private func deliver() {
    guard !disposed, delivering == nil else { return }
    while let completion = completions.first, completion.token <= acknowledged {
      delivering = completion
      let accepted = emit(completion)
      delivering = nil
      if !accepted { break }
      completions.removeFirst()
    }
  }

  private func beginSampling() {
    guard automaticallySample else { return }
    sampling = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        guard let self, self.pending != nil, !self.disposed else { return }
        self.sample()
      }
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    if pending?.started != nil { stop?() }
    sampling?.cancel()
    sampling = nil
    pending = nil
    completions.removeAll()
    move = nil
    geometry = nil
    stop = nil
    owner = nil
  }
}

#if os(macOS)
  @MainActor final class ListScrollNativeHost {
    private final class Row {
      weak var view: NSView?
      init(_ view: NSView) { self.view = view }
    }
    private var rows: [RenderIdentity: Row] = [:]
    private weak var scroll: NSScrollView?

    func register(_ view: NSView, row: RenderIdentity) { rows[row] = Row(view) }
    func remove(_ view: NSView, row: RenderIdentity) {
      if rows[row]?.view === view { rows.removeValue(forKey: row) }
    }
    func geometry(_ row: RenderIdentity) -> ListScrollGeometry? {
      guard let view = rows[row]?.view, view.window != nil,
        let scroll = view.enclosingScrollView, let table = scroll.documentView as? NSTableView
      else { return nil }
      self.scroll = scroll
      var ancestor: NSView? = view
      while let current = ancestor, !(current is NSTableRowView) { ancestor = current.superview }
      guard let rowView = ancestor as? NSTableRowView else { return nil }
      let index = table.row(for: rowView)
      guard index >= 0 else { return nil }
      let viewport = scroll.contentView.bounds
      return ListScrollGeometry(
        row: table.rect(ofRow: index), viewport: viewport,
        minimumOffset: table.bounds.minY,
        maximumOffset: max(table.bounds.minY, table.bounds.maxY - viewport.height))
    }
    func stop() {
      let scroll = self.scroll ?? rows.values.compactMap { $0.view?.enclosingScrollView }.first
      guard let scroll else { return }
      let position = scroll.contentView.bounds.origin
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        scroll.contentView.animator().setBoundsOrigin(position)
      }
      scroll.contentView.layer?.removeAllAnimations()
      scroll.contentView.scroll(to: position)
      scroll.reflectScrolledClipView(scroll.contentView)
    }
  }

  struct NativeListRowProbe: NSViewRepresentable {
    let row: RenderIdentity
    let host: ListScrollNativeHost
    final class Coordinator {
      let row: RenderIdentity
      let host: ListScrollNativeHost
      init(row: RenderIdentity, host: ListScrollNativeHost) {
        self.row = row
        self.host = host
      }
    }
    func makeCoordinator() -> Coordinator { Coordinator(row: row, host: host) }
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityElement(false)
      host.register(view, row: row)
      return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
      coordinator.host.remove(view, row: coordinator.row)
    }
  }
#else
  @MainActor final class ListScrollNativeHost {
    private final class Row {
      weak var view: UIView?
      init(_ view: UIView) { self.view = view }
    }
    private var rows: [RenderIdentity: Row] = [:]
    private weak var scroll: UIScrollView?

    func register(_ view: UIView, row: RenderIdentity) { rows[row] = Row(view) }
    func remove(_ view: UIView, row: RenderIdentity) {
      if rows[row]?.view === view { rows.removeValue(forKey: row) }
    }
    func geometry(_ row: RenderIdentity) -> ListScrollGeometry? {
      guard let view = rows[row]?.view, view.window != nil else { return nil }
      var ancestor: UIView? = view
      var cell: UIView?
      while let current = ancestor, !(current is UIScrollView) {
        if current is UICollectionViewCell || current is UITableViewCell { cell = current }
        ancestor = current.superview
      }
      guard let scroll = ancestor as? UIScrollView, let cell else { return nil }
      self.scroll = scroll
      let insets = scroll.adjustedContentInset
      let viewport = CGRect(
        x: scroll.contentOffset.x, y: scroll.contentOffset.y + insets.top,
        width: scroll.bounds.width, height: scroll.bounds.height - insets.top - insets.bottom)
      return ListScrollGeometry(
        row: cell.convert(cell.bounds, to: scroll), viewport: viewport,
        minimumOffset: 0, maximumOffset: max(0, scroll.contentSize.height - viewport.height))
    }
    func stop() {
      let scroll =
        self.scroll
        ?? rows.values.compactMap { row -> UIScrollView? in
          var ancestor = row.view
          while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
          return ancestor as? UIScrollView
        }.first
      guard let scroll else { return }
      scroll.setContentOffset(scroll.contentOffset, animated: false)
    }
  }

  struct NativeListRowProbe: UIViewRepresentable {
    let row: RenderIdentity
    let host: ListScrollNativeHost
    final class Coordinator {
      let row: RenderIdentity
      let host: ListScrollNativeHost
      init(row: RenderIdentity, host: ListScrollNativeHost) {
        self.row = row
        self.host = host
      }
    }
    func makeCoordinator() -> Coordinator { Coordinator(row: row, host: host) }
    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.isAccessibilityElement = false
      host.register(view, row: row)
      return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
      coordinator.host.remove(view, row: coordinator.row)
    }
  }
#endif

struct NativeListScrollModifier: ViewModifier {
  let controller: ListScrollController
  let proxy: ScrollViewProxy
  @State private var owner = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .onAppear {
        controller.reducedMotion = reduceMotion
        controller.attach(
          owner: owner,
          move: { identity, anchor, animated in
            var transaction = Transaction(animation: animated ? .default : nil)
            transaction.disablesAnimations = !animated
            withTransaction(transaction) {
              proxy.scrollTo(identity, anchor: UnitPoint(x: 0.5, y: CGFloat(anchor) / 2))
            }
          }, geometry: { controller.nativeHost.geometry($0) },
          stop: { controller.nativeHost.stop() })
      }
      .onDisappear { controller.detach(owner: owner) }
      .onChange(of: reduceMotion) { _, value in controller.reducedMotion = value }
      .onScrollPhaseChange { _, phase in
        if phase == .tracking || phase == .interacting { controller.userInteraction() }
      }
  }
}
