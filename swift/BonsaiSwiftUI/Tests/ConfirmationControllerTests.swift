import AppKit
import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor struct ConfirmationControllerTests {
  private func properties(_ token: Int64? = 1) -> RenderConfirmation {
    RenderConfirmation(
      style: 0,
      request: token.map {
        .init(
          token: $0, title: "Delete entry?", message: "This removes the entry.",
          actions: [
            .init(key: "delete", title: "Delete", role: 2, enabled: true),
            .init(key: "cancel", title: "Cancel", role: 1, enabled: true),
            .init(key: "disabled", title: "Unavailable", role: 0, enabled: false),
          ])
      })
  }

  @Test(arguments: [false, true])
  func buttonWinsBothNativeCallbackOrders(dismissFirst: Bool) async throws {
    let controller = ConfirmationController(properties())
    var responses: [ConfirmationController.Response] = []
    controller.setActive(true)
    let opening = try #require(
      controller.opening(handler: 19) {
        responses.append($0)
        return true
      })
    if dismissFirst { controller.dismissed(opening) }
    controller.choose("delete", in: opening)
    if !dismissFirst { controller.dismissed(opening) }
    await nextTurn()
    #expect(responses.map(\.result) == [.action("delete")])
    #expect(responses.map(\.token) == [1])
    #expect(responses.map(\.handler) == [19])
    let request = try #require(controller.pending)
    #expect(!controller.presented)
    controller.resolve(request)
    #expect(controller.presented)
    controller.choose("delete", in: opening)
    controller.dismissed(opening)
    await nextTurn()
    #expect(responses.count == 1)
  }

  @Test func dismissalSettlesOnceAndDisabledActionsDoNotConsumeIt() async throws {
    let controller = ConfirmationController(properties())
    var results: [ConfirmationController.Result] = []
    controller.setActive(true)
    let opening = try #require(
      controller.opening(handler: 3) {
        results.append($0.result)
        return true
      })
    controller.choose("disabled", in: opening)
    controller.choose("missing", in: opening)
    #expect(results.isEmpty)
    controller.dismissed(opening)
    controller.dismissed(opening)
    #expect(results.isEmpty)
    await nextTurn()
    #expect(results == [.dismissed])
  }

  @Test(arguments: ["token", "binding", "hidden", "configuration", "disposed"])
  func retainedCallbacksNeverTargetANewPresentation(change: String) async throws {
    let controller = ConfirmationController(properties())
    var old: [ConfirmationController.Response] = []
    var fresh: [ConfirmationController.Response] = []
    controller.setActive(true)
    let opening = try #require(
      controller.opening(handler: 3) {
        old.append($0)
        return true
      })
    controller.dismissed(opening)
    switch change {
    case "token": controller.synchronize(properties(2))
    case "binding": controller.invalidateBinding()
    case "hidden":
      controller.setActive(false)
      controller.setActive(true)
    case "configuration":
      var next = properties()
      next.request?.title = "Updated title"
      controller.synchronize(next)
    default: controller.dispose()
    }
    controller.choose("delete", in: opening)
    await nextTurn()
    #expect(old.isEmpty)
    if change == "disposed" {
      #expect(
        controller.opening(handler: 4) {
          fresh.append($0)
          return true
        } == nil)
    } else {
      let replacement = try #require(
        controller.opening(handler: 4) {
          fresh.append($0)
          return true
        })
      controller.choose("cancel", in: replacement)
      #expect(fresh.map(\.handler) == [4])
      #expect(fresh.map(\.token) == [change == "token" ? 2 : 1])
      #expect(fresh.map(\.result) == [.action("cancel")])
    }
  }

  @Test func rejectedAdmissionConsumesResponseWithoutReplayingDestructiveAction() async throws {
    let controller = ConfirmationController(properties())
    var attempts = 0
    controller.setActive(true)
    let opening = try #require(
      controller.opening(handler: 3) { _ in
        attempts += 1
        return false
      })
    controller.choose("delete", in: opening)
    controller.dismissed(opening)
    await nextTurn()
    #expect(attempts == 1)
    #expect(controller.pending == nil)
    #expect(controller.presented)
    controller.invalidateBinding()
    let restored = try #require(
      controller.opening(handler: 4) { _ in
        attempts += 1
        return true
      })
    controller.choose("delete", in: restored)
    controller.dismissed(restored)
    await nextTurn()
    #expect(attempts == 1)
  }

  @Test func oldSettlementCannotRestoreClearedOrReplaceNewToken() throws {
    for next: Int64? in [nil, 2] {
      let controller = ConfirmationController(properties())
      controller.setActive(true)
      let opening = try #require(controller.opening(handler: 3) { _ in true })
      controller.choose("delete", in: opening)
      let request = try #require(controller.pending)
      controller.synchronize(properties(next))
      controller.resolve(request)
      #expect(controller.presented == (next != nil))
      #expect(controller.properties.request?.token == next)
    }
  }

  @Test func freshTokensIncreaseWithinOnePresenter() throws {
    let controller = ConfirmationController(properties())
    #expect(throws: Never.self) { try controller.validate(properties()) }
    #expect(throws: Never.self) { try controller.validate(properties(2)) }
    controller.synchronize(properties(nil))
    #expect(throws: TreeError.self) { try controller.validate(properties()) }
    controller.synchronize(properties(2))
    #expect(throws: TreeError.self) { try controller.validate(properties()) }
    #expect(throws: Never.self) { try controller.validate(properties(2)) }
  }

  private func nextTurn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

extension TreeFixture {
  static func confirmation(_ token: Int64? = 1, style: UInt8 = 0, handler: UInt64 = 91)
    -> WireOperation
  {
    operation(OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(152))
      $0.integer(style)
      $0.integer(UInt8(token == nil ? 0 : 1))
      if let token { $0.integer(token) }
      try! $0.string(token == nil ? "" : "Delete entry?")
      $0.integer(UInt8(0))
      $0.integer(UInt16(token == nil ? 0 : 1))
      if token != nil {
        try! $0.string("delete")
        try! $0.string("Delete")
        $0.integer(UInt8(1))
        $0.integer(UInt8(2))
      }
      $0.integer(UInt16(token == nil ? 0 : 1))
      if token != nil {
        $0.integer(UInt16(60))
        $0.integer(handler)
      }
    }
  }
}

extension ConfirmationControllerTests {
  @Test func confirmationWireRejectsMalformedPresentationAndPreservesTheBase() throws {
    for token: Int64? in [nil, 1] {
      let store = try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.confirmation(token), TreeFixture.text(2, "Base"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ])
      ).tree
      let tree = RenderTree()
      tree.commit(store)
      #expect(tree.root?.confirmationController != nil)
      #expect(tree.root?.children.first === tree.nodes[2])
    }
    for operation in [
      TreeFixture.confirmation(0), TreeFixture.confirmation(-1),
      TreeFixture.confirmation(1, style: 2),
    ] {
      #expect(throws: TreeError.self) {
        _ = try NodeStore().staging(
          TreeFixture.frame([
            operation, TreeFixture.text(2, "Base"), TreeFixture.children(1, [2]),
            TreeFixture.root(1),
          ]))
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [false, true]) @MainActor
  func actualConfirmationKeepsOcamlAuthorityAndBlocksBackground(ignore: Bool) async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains {
              if case .text(let value) = $0.properties { return value.value == title }
              return false
            }
          }
          return false
        })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func contains(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    do {
      try await session.start(entrypoint: "native-confirmation")
      #expect(try await session.presented(#require(session.ticket)))
      if ignore {
        #expect(session.activate(try button("Ignore confirmation response")))
        try await flush()
      }
      let background = try button("Background action")
      #expect(session.activate(try button("Show alert")))
      try await flush()
      let node = try #require(session.tree.confirmationNodes.first)
      let controller = try #require(node.confirmationController)
      let opening = try #require(controller.current)
      #expect(controller.active && controller.presented)
      #expect(!session.activate(background))
      controller.dismissed(opening)
      controller.choose("delete", in: opening)
      try await flush()
      #expect(controller.pending == nil)
      if ignore {
        #expect(controller.presented)
        #expect(contains("Confirmation responses: 0"))
        #expect(!session.activate(background))
        let restored = try #require(controller.current)
        controller.choose("delete", in: restored)
        try await flush()
        #expect(contains("Confirmation responses: 0"))
      } else {
        #expect(!controller.presented)
        #expect(contains("Confirmation responses: 1"))
        #expect(contains("Confirmation result: delete"))
        #expect(session.activate(background))
        try await flush()
        #expect(contains("Background actions: 1"))
        #expect(session.activate(try button("Show confirmation dialog")))
        try await flush()
        #expect(node === session.tree.confirmationNodes.first)
        #expect(controller.properties.style == 1)
        controller.choose("delete", in: opening)
        #expect(controller.pending == nil)
        let fresh = try #require(controller.current)
        controller.choose("cancel", in: fresh)
        try await flush()
        #expect(contains("Confirmation responses: 2"))
        #expect(contains("Confirmation result: cancel"))
      }
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [(false, false), (true, false), (false, true), (true, true)]) @MainActor
  func actualNativeConfirmationRendersAndResponds(scenario: (Bool, Bool)) async throws {
    let (dialog, ignore) = scenario
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-confirmation")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingController(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }
        ).frame(width: 650, height: 400))
      let window = NSWindow(contentViewController: host)
      window.makeKeyAndOrderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentViewController = nil
      }
      try await settleAccessibility(host.view)
      if ignore {
        let toggle = try #require(
          session.tree.nodes.values.first { node in
            if case .button = node.properties {
              return node.children.contains {
                if case .text(let text) = $0.properties {
                  return text.value == "Ignore confirmation response"
                }
                return false
              }
            }
            return false
          })
        #expect(session.activate(toggle))
        _ = try await session.refresh()
        #expect(try await session.presented(#require(session.ticket)))
      }
      let show = try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains {
              if case .text(let value) = $0.properties {
                return value.value == (dialog ? "Show confirmation dialog" : "Show alert")
              }
              return false
            }
          }
          return false
        })
      let owner = try #require(session.tree.confirmationNodes.first)
      let base = try #require(owner.children.first)
      #expect(session.activate(show))
      _ = try await session.refresh()
      #expect(try await session.presented(#require(session.ticket)))
      var controls: [AccessibilityElement] = []
      for _ in 0..<30 {
        try await settleAccessibility(host.view)
        controls = NSApp.windows.filter(\.isVisible).flatMap { accessibilityElements($0) }
        if controls.contains(where: { $0.role == "AXButton" && $0.label == "Delete entry" }) {
          break
        }
      }
      let delete = try #require(
        controls.first { $0.role == "AXButton" && $0.label == "Delete entry" })
      #expect(controls.contains { $0.role == "AXButton" && $0.label == "Keep entry" })
      #expect(
        controls.contains {
          $0.role == "AXButton" && $0.label == "Unavailable action" && !$0.enabled
        })
      let nativeDelete = try #require((delete.object as? NSButtonCell)?.controlView as? NSButton)
      #expect(nativeDelete.hasDestructiveAction)
      _ = delete.press()
      try await settleAccessibility(host.view)
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties {
            return value.value == "Confirmation responses: \(ignore ? 0 : 1)"
          }
          return false
        })
      #expect(owner.children.first === base)
      #expect(owner.confirmationController?.presented == ignore)
      if ignore {
        var restored = false
        for _ in 0..<30 {
          try await settleAccessibility(host.view)
          let visibleWindows = NSApp.windows.filter { $0.isVisible }
          let visibleControls: [AccessibilityElement] = visibleWindows.flatMap {
            accessibilityElements($0)
          }
          restored = visibleControls.contains { control in
            control.role == "AXButton" && control.label == "Delete entry" && !control.enabled
          }
          if restored { break }
        }
        #expect(restored)
      }
      await session.close()
      try await settleAccessibility(host.view)
    } catch {
      await session.close()
      throw error
    }
  }
}
