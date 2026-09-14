// Diagnostic for the backend decision's native List experiment. This executable
// is not linked into BonsaiSwiftUI and does not render or capture the Mail app.
import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class Probe {
  @ObservationIgnored var geometry: [CGRect] = []
  @ObservationIgnored var appeared: Set<Int> = []
  var expanded: Int?
}

struct ProbeList: View {
  let probe: Probe
  let minimumHeight: CGFloat
  var body: some View {
    List(0..<10000, id: \.self) { index in
      Text("Row \(index)")
        .frame(height: probe.expanded == index ? 180 : 40)
        .listRowInsets(EdgeInsets())
        .onAppear { probe.appeared.insert(index) }
    }
    .listStyle(.plain)
    .environment(\.defaultMinListRowHeight, minimumHeight)
    .onScrollGeometryChange(for: CGRect.self) {
      $0.visibleRect
    } action: { _, rect in
      probe.geometry.append(rect)
    }
  }
}

@MainActor func descendants<T: NSView>(_ root: NSView, _: T.Type) -> [T] {
  (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, T.self) }
}

@MainActor func settle(_ hosting: NSView) async throws {
  for _ in 0..<10 {
    try await Task.sleep(for: .milliseconds(20))
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
  }
}

@main struct ListDiagnostic {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    for minimumHeight in [CGFloat(24), 40] {
      let probe = Probe()
      let hosting = NSHostingView(rootView: ProbeList(probe: probe, minimumHeight: minimumHeight))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = hosting
      defer { window.contentView = nil }
      try await settle(hosting)
      print("minimum", minimumHeight, "initial appearance count", probe.appeared.count)
      for scroll in descendants(hosting, NSScrollView.self) {
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 300000))
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      try await settle(hosting)
      for table in descendants(hosting, NSTableView.self) {
        print(
          "after jump: row count", table.numberOfRows, "document height", table.frame.height,
          "row0", table.rect(ofRow: 0), "row5000", table.rect(ofRow: 5000),
          "visible range", table.rows(in: table.visibleRect))
      }
      probe.expanded = 10
      try await settle(hosting)
      for table in descendants(hosting, NSTableView.self) {
        print(
          "expanded row10 to 180: viewport", table.visibleRect,
          "row10", table.rect(ofRow: 10), "row5000", table.rect(ofRow: 5000))
      }
      print("observed scroll geometry", probe.geometry)
    }
  }
}
