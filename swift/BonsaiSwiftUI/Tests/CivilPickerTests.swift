import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func civilControlsStageAndReturnToOcamlOwnedValues() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-civil-events")
      #expect(try await session.presented(#require(session.ticket)))
      let date = try #require(session.tree.nodes.values.first { $0.bindings[46] != nil })
      let time = try #require(session.tree.nodes.values.first { $0.bindings[47] != nil })
      let dateController = try #require(date.civilPickerController)
      let timeController = try #require(time.civilPickerController)
      let historical = CivilSelection.date(CivilDate(year: 1582, month: 10, day: 10))
      #expect(dateController.request(historical, emit: date.emit))
      #expect(dateController.selection == historical)
      try await flush()
      // This fixture records requests but deliberately retains the selected values.
      #expect(dateController.selection == .date(CivilDate(year: 2000, month: 2, day: 29)))
      #expect(timeController.request(.time(CivilTime(hour: 23, minute: 59)), emit: time.emit))
      try await flush()
      #expect(timeController.selection == .time(CivilTime(hour: 12, minute: 0)))
      #expect(!date.emit(.civilTime(CivilTime(hour: 0, minute: 0))))
      #expect(!time.emit(.civilDate(CivilDate(year: 2024, month: 1, day: 1))))
      #expect(!date.emit(.civilDate(CivilDate(year: 1500, month: 2, day: 29))))
      session.isActive = false
      #expect(!dateController.request(historical, emit: date.emit))
      session.isActive = true
      let host = NSHostingView(
        rootView: NativeNodeView(node: try #require(session.tree.root), activate: { _ in }))
      host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width.isFinite)
      await session.close()
      #expect(!dateController.request(historical, emit: date.emit))
      #expect(!timeController.request(.time(CivilTime(hour: 0, minute: 0)), emit: time.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor struct CivilPickerTests {
  private func dateProperties(enabled: Bool = true, day: Int = 29, label: String = "Date") throws
    -> RenderCivilPicker
  {
    .date(
      selection: CivilDate(year: 2024, month: 2, day: day),
      domain: try CivilDateDomain(
        first: CivilDate(year: 2024, month: 2, day: 1),
        last: CivilDate(year: 2025, month: 3, day: 10), allowed: []),
      label: label, enabled: enabled)
  }

  @Test func requestsCoalesceAndResolveWithoutOverwritingNewerSelections() throws {
    let controller = CivilPickerController(try dateProperties())
    var events: [NativeEventPayload] = []
    let emit: (NativeEventPayload) -> Bool = {
      events.append($0)
      return true
    }
    let first = CivilSelection.date(CivilDate(year: 2024, month: 2, day: 28))
    let second = CivilSelection.date(CivilDate(year: 2024, month: 2, day: 27))
    #expect(controller.request(first, emit: emit))
    let request = try #require(controller.pending)
    #expect(controller.request(second, emit: emit))
    controller.synchronize(try dateProperties(day: 28))
    controller.resolve(request)
    #expect(controller.selection == second)
    controller.resolve(try #require(controller.pending))
    #expect(controller.selection == first)
    #expect(events.count == 2)
    #expect(!controller.request(first, emit: emit))
    #expect(!controller.request(.time(CivilTime(hour: 0, minute: 0)), emit: emit))
    #expect(!controller.request(.date(CivilDate(year: 2026, month: 1, day: 1)), emit: emit))
    #expect(!controller.request(second, emit: { _ in false }))
    #expect(controller.selection == first)
  }

  @Test func nativeBindingsClampFieldsAndFenceChangedConfigurationAndDisposal() throws {
    let controller = CivilPickerController(try dateProperties())
    var events: [NativeEventPayload] = []
    let emit: (NativeEventPayload) -> Bool = {
      events.append($0)
      return true
    }
    let year = controller.dateBinding(.year, emit: emit)
    #expect(year.wrappedValue == 2024)
    year.wrappedValue = 2025
    #expect(controller.selection == .date(CivilDate(year: 2025, month: 2, day: 28)))
    let month = controller.dateBinding(.month, emit: emit)
    month.wrappedValue = 3
    #expect(controller.selection == .date(CivilDate(year: 2025, month: 3, day: 10)))
    let stale = controller.dateBinding(.day, emit: emit)
    controller.synchronize(try dateProperties(label: "Replacement"))
    stale.wrappedValue = 4
    #expect(events.count == 2)
    #expect(controller.pending == nil)
    controller.synchronize(try dateProperties(enabled: false))
    controller.dateBinding(.day, emit: emit).wrappedValue = 4
    #expect(events.count == 2)
    controller.dispose()
    #expect(!controller.request(.date(CivilDate(year: 2024, month: 2, day: 5)), emit: emit))
  }

  @Test func clockBindingRejectsInvalidDatesAndRestoresRejectedEdits() throws {
    let properties = RenderCivilPicker.time(
      selection: CivilTime(hour: 12, minute: 0), format: .hour24, label: "Time", enabled: true)
    let controller = CivilPickerController(properties)
    let binding = controller.timeBinding(emit: { _ in true })
    binding.wrappedValue = try CivilTime(hour: 0, minute: 0).dateForPicker()
    #expect(controller.selection == .time(CivilTime(hour: 0, minute: 0)))
    binding.wrappedValue = Date(timeIntervalSinceReferenceDate: .infinity)
    #expect(controller.selection == .time(CivilTime(hour: 0, minute: 0)))
    controller.resolve(try #require(controller.pending))
    #expect(controller.selection == properties.selection)
    binding.wrappedValue = try CivilTime(hour: 23, minute: 59).dateForPicker()
    #expect(controller.selection == properties.selection)
  }
}

extension TreeFixture {
  static func civilDateControl(
    handler: UInt64? = 91, enabled: UInt8 = 1, day: UInt8 = 29, label: String = "Date",
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(59))
      if update { $0.integer(UInt64(63)) }
      for (year, month, date) in [(UInt16(2024), UInt8(2), day), (2024, 2, 1), (2025, 3, 10)] {
        $0.integer(year)
        $0.integer(month)
        $0.integer(date)
      }
      $0.integer(UInt16(0))
      try! $0.string(label)
      $0.integer(enabled)
      if !update {
        $0.integer(UInt16(handler == nil ? 0 : 1))
        if let handler {
          $0.integer(UInt16(46))
          $0.integer(handler)
        }
      }
    }
  }
}

extension CivilPickerTests {
  @Test func replacingHandlerInvalidatesNativeBindingsAndPendingRequests() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([TreeFixture.civilDateControl(), TreeFixture.root(1)])
    ).tree
    let tree = RenderTree()
    tree.commit(initial)
    let controller = try #require(tree.root?.civilPickerController)
    var events = 0
    let old = controller.dateBinding(
      .day,
      emit: { _ in
        events += 1
        return true
      })
    old.wrappedValue = 28
    let changed = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(46))
      $0.integer(UInt64(92))
    }
    tree.commit(try initial.staging(TreeFixture.frame([changed], base: 1, revision: 2)).tree)
    old.wrappedValue = 27
    #expect(events == 1)
    #expect(controller.pending == nil)
    #expect(controller.selection == .date(CivilDate(year: 2024, month: 2, day: 29)))
  }

  @Test func malformedDateNodesCannotStageOrMutateAnExistingTree() throws {
    for operation in [
      TreeFixture.civilDateControl(day: 30), TreeFixture.civilDateControl(label: " "),
      TreeFixture.civilDateControl(enabled: 2), TreeFixture.civilDateControl(handler: nil),
      TreeFixture.civilDateControl(enabled: 0),
    ] {
      #expect(throws: (any Error).self) {
        _ = try NodeStore().staging(TreeFixture.frame([operation, TreeFixture.root(1)]))
      }
    }
    let initial = try NodeStore().staging(
      TreeFixture.frame([TreeFixture.civilDateControl(), TreeFixture.root(1)])
    ).tree
    #expect(throws: (any Error).self) {
      _ = try initial.staging(
        TreeFixture.frame(
          [TreeFixture.civilDateControl(day: 30, update: true)], base: 1, revision: 2))
    }
    #expect(initial.revision == 1)
    #expect(initial.nodes[1]?.bindings[46] == 91)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryCivilPickersReconcileAcceptanceRejectionAndBindingChanges()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      let text = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === text } })
    }
    do {
      try await session.start(entrypoint: "native-civil-picker")
      #expect(try await session.presented(#require(session.ticket)))
      let date = try #require(session.tree.nodes.values.first { $0.bindings[46] != nil })
      let time = try #require(session.tree.nodes.values.first { $0.bindings[47] != nil })
      let dates = try #require(date.civilPickerController)
      let times = try #require(time.civilPickerController)
      let chosen = CivilSelection.date(CivilDate(year: 2025, month: 2, day: 28))
      dates.dateBinding(.year, emit: date.emit).wrappedValue = 2025
      try await flush()
      #expect(dates.selection == chosen)
      times.timeBinding(emit: time.emit).wrappedValue = try CivilTime(hour: 23, minute: 59)
        .dateForPicker()
      try await flush()
      #expect(times.selection == .time(CivilTime(hour: 23, minute: 59)))
      let old = dates.dateBinding(.day, emit: date.emit)
      #expect(session.activate(try button("Replace civil handlers")))
      _ = try await session.refresh()
      // The replacement is staged but has not been presented.
      #expect(!dates.request(.date(CivilDate(year: 2025, month: 2, day: 27)), emit: date.emit))
      #expect(try await session.presented(#require(session.ticket)))
      old.wrappedValue = 27
      #expect(!(try await session.refresh()))
      #expect(dates.selection == chosen)
      #expect(session.activate(try button("Ignore civil changes")))
      try await flush()
      for _ in 0..<2 {
        #expect(times.request(.time(CivilTime(hour: 0, minute: 0)), emit: time.emit))
        #expect(!(try await session.refresh()))
        #expect(times.selection == .time(CivilTime(hour: 23, minute: 59)))
      }
      #expect(session.activate(try button("Accept civil changes")))
      try await flush()
      #expect(session.activate(try button("Restrict dates")))
      try await flush()
      #expect(!dates.request(chosen, emit: date.emit))
      dates.dateBinding(.year, emit: date.emit).wrappedValue = 2025
      try await flush()
      #expect(dates.selection == .date(CivilDate(year: 2025, month: 1, day: 2)))
      #expect(session.activate(try button("Disable civil controls")))
      try await flush()
      #expect(!date.emit(.civilDate(CivilDate(year: 2025, month: 3, day: 10))))
      #expect(!times.request(.time(CivilTime(hour: 0, minute: 0)), emit: time.emit))
      #expect(session.activate(try button("Enable civil controls")))
      try await flush()
      session.isVisible = false
      #expect(!date.emit(.civilDate(CivilDate(year: 2025, month: 3, day: 10))))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeCivilFieldActionsReachTheActualOcamlModel() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    do {
      try await session.start(entrypoint: "native-civil-picker")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(node: try #require(session.tree.root), activate: { _ in }))
      window.contentView = host
      window.orderFront(nil)
      try await settleAccessibility(host)
      var views = [host as NSView]
      var year: NSPopUpButton?
      var clock: NSDatePicker?
      while let view = views.popLast() {
        if let popup = view as? NSPopUpButton,
          popup.itemArray.contains(where: { $0.title == "2025" })
        {
          year = popup
        }
        if let picker = view as? NSDatePicker { clock = picker }
        views.append(contentsOf: view.subviews)
      }
      let yearControl = try #require(year)
      let clockControl = try #require(clock)
      let menu = try #require(yearControl.menu)
      let item = try #require(menu.items.first { $0.title == "2025" })
      #expect(item.action != nil)
      menu.performActionForItem(at: menu.index(of: item))
      try await settleAccessibility(host)
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      let dates = try #require(
        session.tree.nodes.values.first { $0.bindings[46] != nil }?.civilPickerController)
      #expect(dates.selection == .date(CivilDate(year: 2025, month: 2, day: 28)))
      clockControl.dateValue = try CivilTime(hour: 15, minute: 42).dateForPicker()
      #expect(clockControl.sendAction(clockControl.action, to: clockControl.target))
      try await settleAccessibility(host)
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      let times = try #require(
        session.tree.nodes.values.first { $0.bindings[47] != nil }?.civilPickerController)
      #expect(times.selection == .time(CivilTime(hour: 15, minute: 42)))
      #expect(clockControl.timeZone?.secondsFromGMT() == 0)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
