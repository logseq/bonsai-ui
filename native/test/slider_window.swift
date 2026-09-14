import AppKit
import SwiftUI

@MainActor private final class SliderWindowModel {
  let vertical = CommandLine.arguments.contains("--vertical")
  let upperFirst = CommandLine.arguments.contains("--upper-first")
  let rtl = CommandLine.arguments.contains("--rtl")
  let tree = RenderTree()
  var events: [NativeEventPayload] = []
  var contentFrame: CGRect = .zero
  init() {
    tree.commit(
      try! NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.slider(lower: 50, upper: 50, vertical: vertical ? 1 : 0), TreeFixture.root(1),
        ])
      ).tree)
    tree.onInput = { [weak self] _, event in
      self?.events.append(event)
      return true
    }
  }
  var size: CGSize { CGSize(width: vertical ? 80 : 300, height: vertical ? 300 : 80) }
}

@main struct SliderWindowAcceptance: App {
  private let model = SliderWindowModel()
  var body: some Scene {
    Window("Slider Acceptance", id: "slider") {
      NativeNodeView(node: model.tree.root!, activate: { _ in })
        .frame(width: model.size.width, height: model.size.height)
        .environment(\.layoutDirection, model.rtl ? .rightToLeft : .leftToRight)
        .allowsWindowActivationEvents(true)
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .global)
        } action: {
          model.contentFrame = $0
        }
        .task { await verify(model) }
    }.defaultSize(width: model.size.width, height: model.size.height)
  }
}

@MainActor private func verify(_ model: SliderWindowModel) async {
  do {
    let window = try require(NSApp.windows.first { $0.contentView != nil })
    let host = try require(window.contentView)
    window.setContentSize(model.size)
    try await settleAccessibility(host)
    func point(_ value: Double) -> CGPoint {
      let fraction = value / 100
      let point =
        model.vertical
        ? CGPoint(x: 40, y: 22 + (1 - fraction) * 256)
        : CGPoint(x: 22 + (model.rtl ? 1 - fraction : fraction) * 256, y: 40)
      return CGPoint(x: model.contentFrame.minX + point.x, y: model.contentFrame.minY + point.y)
    }
    let first = model.upperFirst ? 80.0 : 20.0
    let firstExpected =
      model.upperFirst
      ? SliderSelection(lower: 50, upper: 80) : SliderSelection(lower: 20, upper: 50)
    let scenarios: [(Double, Double, SliderSelection)] = [
      (50, first, firstExpected),
      (50, model.upperFirst ? 20 : 80, SliderSelection(lower: 20, upper: 80)),
      (20, 95, SliderSelection(lower: 80, upper: 80)),
      (80, 100, SliderSelection(lower: 80, upper: 100)),
      (100, 0, SliderSelection(lower: 80, upper: 80)),
      (80, 0, SliderSelection(lower: 0, upper: 80)),
    ]
    for (index, scenario) in scenarios.enumerated() {
      try await drag(host, from: point(scenario.0), to: point(scenario.1))
      guard model.tree.root!.sliderController!.selection == scenario.2,
        model.events.last?.sliderSelection == scenario.2,
        model.events.filter({ $0.tag == EventTagId.rangeSliderChangeEnd }).count == index + 1
      else {
        throw failure(
          "Drag \(index): \(model.tree.root!.sliderController!.selection); expected \(scenario.2); events: \(model.events)"
        )
      }
    }
    print("PASS: native range sliders drag apart from a collapsed interval")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

@MainActor private func drag(_ host: NSView, from start: CGPoint, to end: CGPoint) async throws {
  let window = try require(host.window)
  let timestamp = ProcessInfo.processInfo.systemUptime
  for step in 0...12 {
    let fraction = Double(step) / 12
    let point = host.convert(
      CGPoint(
        x: start.x + (end.x - start.x) * fraction,
        y: start.y + (end.y - start.y) * fraction), to: nil)
    let type: NSEvent.EventType =
      step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
    let event = try require(
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: timestamp + Double(step) * 0.016,
        windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 1,
        pressure: step == 12 ? 0 : 1))
    NSApp.postEvent(event, atStart: false)
  }
  try await settleAccessibility(host)
}
private func failure(_ text: String) -> NSError {
  NSError(domain: "SliderWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
private func require<T>(_ value: T?) throws -> T {
  guard let value else { throw failure("Missing native object") }
  return value
}
