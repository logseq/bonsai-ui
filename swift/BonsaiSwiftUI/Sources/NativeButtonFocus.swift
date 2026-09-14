import SwiftUI

struct NativeButtonFocus: ViewModifier {
  let controller: FocusScopeController
  let autofocus: Bool
  let activate: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled
  private var available: Bool { controller.isCollecting && enabled }

  func body(content: Content) -> some View {
    content
      .focusable(
        enabled && controller.canRetainFocus && (controller.isCollecting || focused),
        interactions: autofocus ? .edit : .activate
      )
      .focused($focused)
      .onKeyPress(.space, phases: [.down, .repeat, .up]) { press in
        guard available, focused, controller.hasFocus,
          press.modifiers.intersection([.command, .control, .option]).isEmpty
        else { return .ignored }
        if press.phase == .down { activate() }
        return .handled
      }
      .onChange(of: focused, initial: true) { _, value in controller.observeFocus(value) }
      .onChange(of: enabled, initial: true) { _, value in controller.setEnabled(value) }
      .onChange(of: controller.autofocusRequest, initial: true) { _, _ in
        if controller.wantsAutofocus { focused = true }
      }
      .onAppear { controller.setMounted(true) }
      .onDisappear { controller.setMounted(false) }
  }
}
