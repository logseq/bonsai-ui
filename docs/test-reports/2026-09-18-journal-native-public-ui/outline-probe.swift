import AppKit
import SwiftUI

@MainActor final class State {
  var proxy: ScrollViewProxy?
  var observations: [String: NSView] = [:]
  var expanded = true
}
struct RowProbe: NSViewRepresentable {
  let key: String
  let state: State
  func makeNSView(context: Context) -> NSView {
    let view = NSView(); state.observations[key] = view; return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}
struct Outline: View {
  let state: State
  var body: some View {
    ScrollViewReader { proxy in
      List {
        Section {
          ForEach(0..<5, id: \.self) { parent in
            AnyView(DisclosureGroup(isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 })) {
              ForEach(0..<4, id: \.self) { child in
                Text("Child \(parent)-\(child)")
                  .frame(minHeight: 40)
                  .background(RowProbe(key: "child\(parent)-\(child)", state: state))
                  .id("child\(parent)-\(child)")
              }
            } label: {
              Text("Parent \(parent)")
                .frame(minHeight: 40)
                .background(RowProbe(key: "parent\(parent)", state: state))
                .id("parent\(parent)")
                .swipeActions { Button("Delete parent") {} }
                .contextMenu { Button("Context parent") {} }
            })
          }
        } header: { Text("Outline") }
      }.listStyle(.plain)
        .onAppear { state.proxy = proxy }
    }
  }
}
@main struct Main {
  @MainActor static func main() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory); app.finishLaunching()
    let state = State()
    let host = NSHostingView(rootView: Outline(state: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host; window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(300))
    func inspect(_ key: String) {
      guard let view = state.observations[key], let scroll = view.enclosingScrollView,
        let table = scroll.documentView as? NSTableView else { print("missing \(key)"); return }
      var ancestor: NSView? = view
      while let current = ancestor, !(current is NSTableRowView) { ancestor = current.superview }
      guard let row = ancestor as? NSTableRowView else { print("no row \(key)"); return }
      let index = table.row(for: row)
      print("\(key) tableRows=\(table.numberOfRows) index=\(index) row=\(table.rect(ofRow:index)) viewport=\(scroll.contentView.bounds)")
    }
    inspect("parent0"); inspect("child0-0")
    for key in ["parent3", "child3-2", "parent1"] {
      state.proxy?.scrollTo(key, anchor: .top)
      try await Task.sleep(for: .milliseconds(200))
      inspect(key)
    }
    window.orderOut(nil); window.contentView = nil
  }
}
