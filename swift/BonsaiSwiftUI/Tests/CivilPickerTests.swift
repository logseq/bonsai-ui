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
      let historical = CivilSelection.date(CivilDate(year: 1582, month: 10, day: 15))
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

extension TreeFixture {
  static func civilDateControl(
    handler: UInt64? = 91, enabled: UInt8 = 1, day: UInt8 = 29, label: String = "Date",
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(59))
      if update { $0.integer(UInt64(31)) }
      for (year, month, date) in [(UInt16(2024), UInt8(2), day), (2024, 2, 1), (2025, 3, 10)] {
        $0.integer(year)
        $0.integer(month)
        $0.integer(date)
      }
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

@MainActor struct CivilPickerTests {
  @Test func dateBindingRejectsStaleDisabledAndUnadmittedSelections() throws {
    let first = CivilDate(year: 2024, month: 2, day: 29)
    let next = CivilDate(year: 2025, month: 3, day: 10)
    let domain = try CivilDateDomain(first: first, last: next)
    let properties = RenderCivilPicker.date(
      selection: first, domain: domain, label: "Date", enabled: true)
    let controller = CivilPickerController(properties)
    var events: [NativeEventPayload] = []
    let binding = controller.dateBinding {
      events.append($0)
      return true
    }
    #expect(try CivilDate.fromPickerDate(binding.wrappedValue) == first)
    binding.wrappedValue = try next.dateForPicker()
    #expect(controller.selection == .date(next))
    let pending = try #require(controller.pending)
    controller.resolve(pending)
    #expect(controller.selection == .date(first))
    binding.wrappedValue = try next.dateForPicker()
    #expect(events.count == 1)
    let rejected = controller.dateBinding { _ in false }
    rejected.wrappedValue = try next.dateForPicker()
    #expect(controller.selection == .date(first))
    let stale = controller.dateBinding {
      events.append($0)
      return true
    }
    controller.synchronize(
      .date(selection: first, domain: domain, label: "Replacement", enabled: false))
    stale.wrappedValue = try next.dateForPicker()
    #expect(events.count == 1)
    controller.dispose()
    #expect(!controller.request(.date(next), emit: { _ in true }))
  }
}
