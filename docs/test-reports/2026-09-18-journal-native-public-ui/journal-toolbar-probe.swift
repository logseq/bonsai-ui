import SwiftUI
struct Probe: View {
  let items: [Int]
  var body: some View {
    Text("Body").toolbar {
      ForEach(items, id: \.self) { item in
        ToolbarItemGroup(placement: .primaryAction) { Button("Item \(item)") {} }
      }
    }
  }
}
