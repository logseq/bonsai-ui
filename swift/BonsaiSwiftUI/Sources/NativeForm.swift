import SwiftUI

struct NativeSection: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void

  @ViewBuilder var body: some View {
    if case .section(let hasHeader, let hasFooter) = node.properties {
      Section {
        ForEach(Array(node.children.dropFirst(2))) { row in
          NativeNodeView(node: row, activate: activate)
        }
      } header: {
        if hasHeader { NativeNodeView(node: node.children[0], activate: activate) }
      } footer: {
        if hasFooter { NativeNodeView(node: node.children[1], activate: activate) }
      }
    }
  }
}

struct NativeForm: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    Form {
      ForEach(node.children) { row in
        NativeNodeView(node: row, activate: activate)
      }
    }.formStyle(.grouped)
  }
}

struct NativeTextSelection: ViewModifier {
  let enabled: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if enabled { content.textSelection(.enabled) } else { content.textSelection(.disabled) }
  }
}
