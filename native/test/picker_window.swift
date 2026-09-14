import AppKit
import SwiftUI

@main struct PickerWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Picker Acceptance", id: "picker-acceptance") {
      BonsaiApplicationView(entrypoint: "native-picker", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 680)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 720)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing Picker window") }
    func pickers() -> [RenderNodeState] {
      session.tree.nodes.values.filter {
        if case .picker(let properties) = $0.properties {
          return ["Automatic", "Menu", "Segmented", "Inline"].contains(properties.label)
        }
        return false
      }
    }
    func settled(_ selection: Int64) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if pickers().count == 4, session.ticket == nil,
          pickers().allSatisfy({
            $0.pickerController?.selection == selection && $0.pickerController?.pending == nil
          })
        {
          return
        }
      }
      throw failure("Picker selection did not settle to \(selection)")
    }
    func choices(_ label: String) -> [AccessibilityElement] {
      accessibilityElements(host).filter { $0.role == "AXRadioButton" && $0.label == label }
    }
    func button(_ label: String) throws {
      guard
        let button = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == label && $0.enabled
        }), button.press()
      else { throw failure("Cannot press \(label)") }
    }
    try await settled(-1)
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 720))
      try await settleAccessibility(host)
      guard choices("Second").count == 2, choices("Disabled").count == 2,
        choices("Disabled").allSatisfy({ !$0.enabled })
      else {
        throw failure("Missing or incorrectly enabled radio/segment choices")
      }
      for index in 0..<2 {
        _ = choices("Second")[index].press()
        try await settled(2)
        guard choices("Second").allSatisfy({ $0.numericValue == 1 }) else {
          throw failure("Native selected state did not follow OCaml")
        }
        _ = choices("First")[index].press()
        try await settled(-1)
        try button("Ignore picker changes")
        for _ in 0..<100 {
          try await settleAccessibility(host)
          if session.ticket == nil,
            accessibilityElements(host).contains(where: { $0.label == "Accept picker changes" })
          {
            break
          }
        }
        _ = choices("Second")[index].press()
        guard pickers().contains(where: { $0.pickerController?.pending?.value == 2 }) else {
          throw failure("Native choice did not queue an OCaml request")
        }
        try await settled(-1)
        guard choices("Second").allSatisfy({ $0.numericValue == 0 }) else {
          throw failure("Rejected choice remained selected")
        }
        try button("Accept picker changes")
        for _ in 0..<100 {
          try await settleAccessibility(host)
          if session.ticket == nil,
            accessibilityElements(host).contains(where: { $0.label == "Ignore picker changes" })
          {
            break
          }
        }
      }
      for option in choices("Disabled") { _ = option.press() }
      guard pickers().allSatisfy({ $0.pickerController?.pending == nil }) else {
        throw failure("A disabled choice emitted an event")
      }
    }
    await session.close()
    print(
      "PASS: actual Gallery Picker native radio and segmented choices accept, reject and disable at both widths"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

private func failure(_ text: String) -> NSError {
  NSError(domain: "PickerWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
