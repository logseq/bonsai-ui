import SwiftUI
import AppKit
import Observation
@MainActor @Observable final class State {
 var expanded = true
 var actions = 0
}
struct Probe: View {
 let state: State
 let style: Int
 let wrap: Bool
 @ViewBuilder var label: some View {
  let button = Button("Open parent") { state.actions += 1 }
  switch style {
  case 0: button.buttonStyle(.automatic)
  case 1: button.buttonStyle(.plain)
  case 2: button.buttonStyle(.borderless)
  default: button.buttonStyle(.bordered)
  }
 }
 var body: some View {
  List {
   DisclosureGroup(isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 })) {
    Text("Child")
   } label: {
    if wrap { HStack { label } } else { label }
   }
  }.listStyle(.plain)
 }
}
@main struct Main {
 @MainActor static func main() async throws {
  initializeAccessibilityApplication()
  for wrap in [false, true] {
   for style in 0...3 {
    let state = State()
    let host = NSHostingView(rootView: Probe(state: state, style: style, wrap: wrap))
    let window = NSWindow(contentRect: CGRect(x:0,y:0,width:400,height:300), styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView = host; window.orderFront(nil)
    try await settleAccessibility(host)
    func elements(_ view: NSView) -> [AccessibilityElement] {
     if let table = view as? NSTableView {
      return (0..<table.numberOfRows).flatMap { table.view(atColumn:0,row:$0,makeIfNecessary:true).map(accessibilityElements) ?? [] }
     }
     return view.subviews.flatMap(elements)
    }
    func nativeButtons(_ view: NSView) -> [NSButton] {
      (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(nativeButtons)
    }
    if !wrap && style == 0 { print("NATIVE BUTTONS", nativeButtons(host).map { (String(describing:type(of:$0)), $0.title, $0.bezelStyle.rawValue, $0.frame) }) }
    let entries = elements(host).filter { $0.label == "Open parent" }
    print("before wrap=\(wrap) style=\(style) roles=\(entries.map { $0.role ?? "nil" })")
    if let entry = entries.first { print("press \(entry.press())") }
    try await Task.sleep(for:.milliseconds(20))
    print("after expanded=\(state.expanded) actions=\(state.actions)")
    window.orderOut(nil); window.contentView = nil
   }
  }
 }
}
