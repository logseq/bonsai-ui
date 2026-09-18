import SwiftUI
import AppKit

struct DynamicToolbar: ToolbarContent {
  let groups: [Int]
  func compose(_ groups: ArraySlice<Int>) -> any ToolbarContent {
    guard let first = groups.first else {
      return ToolbarItemGroup(placement: .primaryAction) { EmptyView() }
    }
    let head = ToolbarItemGroup(placement: .primaryAction) {
      ForEach([first], id: \.self) { item in TextField("Group \(item)", text: .constant("Value \(item)")) }
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
      dump("Before")
      state.groups = [2,1]
      try? await Task.sleep(for: .milliseconds(200))
      dump("Reordered")
      app.terminate(nil)
    }
    app.run()
  }
}
