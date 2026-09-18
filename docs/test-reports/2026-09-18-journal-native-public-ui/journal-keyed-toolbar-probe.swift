import SwiftUI
import AppKit

struct DynamicToolbar: ToolbarContent {
  let groups: [Int]
  func compose(_ groups: ArraySlice<Int>) -> any ToolbarContent {
    guard let first = groups.first else {
      return ToolbarItemGroup(placement: .primaryAction) { EmptyView() }
    }
    let head = ToolbarItem(id: "group-\(first)", placement: .primaryAction) {
      ControlGroup {
        ForEach([first], id: \.self) { item in
          TextField("Group \(item)", text: .constant("Value \(item)"))
        }
      }
    }
    let tail = ToolbarContentBuilder.buildLimitedAvailability(compose(groups.dropFirst()))
    return ToolbarContentBuilder.buildBlock(head, tail)
  }
  var body: some ToolbarContent {
    ToolbarContentBuilder.buildLimitedAvailability(compose(groups[...]))
  }
}

@Observable @MainActor final class State {
  var groups = [1,2]
}
struct Root: View {
  let state: State
  var body: some View {
    Text("Stable body").frame(width: 500, height: 300)
      .toolbar { DynamicToolbar(groups: state.groups) }
  }
}

@main struct Probe {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let state = State()
    let host = NSHostingController(rootView: Root(state: state))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.orderFront(nil)
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(200))
      @MainActor func dump(_ phase: String) {
        print(phase, window.toolbar?.items.map { ($0.itemIdentifier.rawValue, $0.label, ($0 as? NSToolbarItemGroup)?.subitems.map(\.itemIdentifier.rawValue) ?? []) } ?? [])
      }
      @MainActor func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
      }
      @MainActor func fields() -> [NSTextField] {
        var pending = window.toolbar?.items ?? []
        var result: [NSTextField] = []
        while let item = pending.popLast() {
          if let view = item.view { result += fields(view) }
          if let group = item as? NSToolbarItemGroup { pending += group.subitems }
        }
        return result
      }
      dump("Before")
      let original = fields()
      print("Fields before", original.map { (ObjectIdentifier($0), $0.stringValue) })
      if let first = original.first { print("Focus accepted", window.makeFirstResponder(first)) }
      state.groups = [2,1]
      try? await Task.sleep(for: .milliseconds(200))
      dump("Reordered")
      let reordered = fields()
      print("Fields after", reordered.map { (ObjectIdentifier($0), $0.stringValue) })
      print("Original editor retained", original.first?.currentEditor() != nil)
      print("Original views retained", !original.isEmpty && original.allSatisfy { old in reordered.contains { $0 === old } })
      app.terminate(nil)
    }
    app.run()
  }
}
