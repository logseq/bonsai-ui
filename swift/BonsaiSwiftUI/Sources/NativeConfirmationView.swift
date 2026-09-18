import SwiftUI

private struct NativeConfirmationPresenter: View {
  let controller: ConfirmationController
  let opening: ConfirmationController.Opening

  private func binding(_ style: Int) -> Binding<Bool> {
    Binding(
      get: {
        controller.active && controller.presented && controller.properties.style == style
          && controller.presentationIdentity == opening.identity
      },
      set: { value in if !value { controller.dismissed(opening) } })
  }

  @ViewBuilder private var actions: some View {
    ForEach(opening.request.actions, id: \.id) { action in
      Button(role: action.role == 1 ? .cancel : action.role == 2 ? .destructive : nil) {
        controller.choose(action.key, in: opening)
      } label: {
        Text(action.title)
      }
      .disabled(!action.enabled || controller.hasResponded)
    }
  }

  var body: some View {
    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      .alert(opening.request.title, isPresented: binding(0)) {
        actions
      } message: {
        if let message = opening.request.message { Text(message) }
      }
      .confirmationDialog(opening.request.title, isPresented: binding(1), titleVisibility: .visible)
    {
      actions
    } message: {
      if let message = opening.request.message { Text(message) }
    }
  }
}

struct NativeConfirmationView: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .background {
        if let controller = node.confirmationController, let opening = controller.current {
          NativeConfirmationPresenter(controller: controller, opening: opening)
            .id(controller.presentationIdentity)
        }
      }
  }
}
