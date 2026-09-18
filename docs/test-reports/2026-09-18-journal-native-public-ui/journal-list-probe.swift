import AppKit
import SwiftUI

@MainActor final class Probe {
  var scroll: ((Int, UnitPoint) -> Void)?
  var frames: [Int: CGRect] = [:]
  var geometry: ScrollGeometry?
  var views: [Int: NSView] = [:]
}
struct RowProbe: NSViewRepresentable {
  let row: Int
  let probe: Probe
  func makeNSView(context: Context) -> NSView { let view = NSView(); probe.views[row] = view; return view }
  func updateNSView(_ view: NSView, context: Context) {}
}
struct ProbeView: View {
  let probe: Probe
  var body: some View {
    ScrollViewReader { proxy in
      List {
        Section {
          ForEach(0..<100, id: \.self) { i in
            Text("Row \(i)")
              .frame(maxWidth: .infinity, minHeight: i == 50 ? 500 : 40)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("viewport")) } action: { probe.frames[i] = $0 }
              .background(RowProbe(row: i, probe: probe))
              .id(i)
          }
        } header: { Text("Header") }
      }
      .listStyle(.plain)
      .coordinateSpace(name: "viewport")
      .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in probe.geometry = geometry }
      .onAppear { probe.scroll = { i, anchor in proxy.scrollTo(i, anchor: anchor) } }
    }
  }
}
@main struct Main {
  @MainActor static func main() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let probe = Probe()
    let host = NSHostingController(rootView: ProbeView(probe: probe))
    let window = NSWindow(contentViewController: host)
    window.setContentSize(NSSize(width: 400, height: 300))
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(500))
    print("initial row80=\(String(describing: probe.frames[80])) geometry=\(String(describing: probe.geometry))")
    for (row, anchor) in [(80, UnitPoint.top), (60, .center), (40, .bottom), (99, .top), (0, .bottom), (50, .center), (80, .top)] {
      let start = ContinuousClock.now
      probe.scroll?(row, anchor)
      try await Task.sleep(for: .milliseconds(300))
      if let view = probe.views[row], let scroll = view.enclosingScrollView { print("native frame=\(view.convert(view.bounds, to: scroll.contentView)) bounds=\(scroll.contentView.bounds)") }
      print("row=\(row) anchor=\(anchor) elapsed=\(start.duration(to: .now)) frame=\(String(describing: probe.frames[row])) geometry=\(String(describing: probe.geometry))")
    }
    window.orderOut(nil)
  }
}
