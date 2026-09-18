import Foundation
import Testing

@testable import BonsaiSwiftUI

enum SwiftInputFixtures {
  static let names = [
    "confirmation_action", "confirmation_dismissed",
    "counter_press", "host_response", "text_edit_unicode",
    "text_limit_reached", "environment_changed", "application_response", "application_event",
  ]
  static var environment: NativeHostEnvironment {
    NativeHostEnvironment(
      viewportWidth: 1440, viewportHeight: 900, devicePixelRatio: 2,
      textScale: 1.25, brightness: .dark, platform: .macos, locale: "zh-CN",
      safeArea: .init(top: 24), keyboardInsets: .init(bottom: 280),
      accessibleNavigation: false, boldText: true, invertColors: false,
      disableAnimations: false, reducedMotion: true, highContrast: true,
      orientation: .landscape, pointerKinds: 10)
  }
  static func encode(_ name: String) throws -> Data {
    let epoch: UInt64
    let event: NativeEvent
    switch name {
    case "confirmation_action", "confirmation_dismissed":
      epoch = 22
      event = NativeEvent(
        sequence: 10, displayedRevision: 2, nodeID: 5, handlerID: 46,
        payload: .confirmationResponse(
          .init(
            serial: UUID(), token: 7, handler: 46,
            result: name == "confirmation_action" ? .action("删除😀") : .dismissed)))
    case "counter_press":
      epoch = 21
      event = NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 3, handlerID: 9001)
    case "host_response":
      epoch = 31
      event = NativeEvent(
        sequence: 2, displayedRevision: 3, nodeID: 0, handlerID: 0,
        payload: .hostResponse(
          HostResponse(
            requestID: 44, status: .error,
            value: Data("denied: 剪贴板😀".utf8))))
    case "text_edit_unicode":
      epoch = 22
      event = NativeEvent(
        sequence: 3, displayedRevision: 2, nodeID: 4, handlerID: 44,
        payload: .textEdit(
          TextEdit(
            sessionID: 7, localRevision: 3, baseDocumentRevision: 2,
            value: try TextValue(
              text: "拼😀音", selection: NSRange(location: 4, length: 0),
              marked: NSRange(location: 0, length: 4)))))
    case "text_limit_reached":
      epoch = 22
      event = NativeEvent(
        sequence: 4, displayedRevision: 2, nodeID: 4, handlerID: 45,
        payload: .textLimitReached)
    case "environment_changed":
      epoch = 31
      event = environmentEvent(environment)
    case "application_response":
      epoch = 41
      event = NativeEvent(
        sequence: 8, displayedRevision: 9, nodeID: 0, handlerID: 0,
        payload: .applicationResponse(501, Data([0, 111, 112, 97, 113, 117, 101, 255])))
    case "application_event":
      epoch = 41
      event = NativeEvent(
        sequence: 9, displayedRevision: 9, nodeID: 0, handlerID: 0,
        payload: .applicationEvent(Data([128, 0, 101, 118, 101, 110, 116])))
    default: throw WireError.invalidHeader
    }
    return try EventBatch.encode(epoch: epoch, events: [event])
  }
  static func environmentEvent(_ value: NativeHostEnvironment, sequence: UInt64 = 4) -> NativeEvent
  {
    NativeEvent(
      sequence: sequence, displayedRevision: 3, nodeID: 0, handlerID: 0,
      payload: .environmentChanged(value))
  }
  static func hex(_ data: Data) -> String {
    data.enumerated().map { index, byte in
      (index == 0 ? "" : index % 12 == 0 ? "\n" : " ") + String(format: "%02x", byte)
    }.joined() + "\n"
  }
}

struct SwiftInputFixtureTests {
  @Test(arguments: SwiftInputFixtures.names)
  func productionEncodingMatchesCommittedFixture(name: String) throws {
    let expected = SwiftInputFixtures.hex(try SwiftInputFixtures.encode(name))
    if let directory = ProcessInfo.processInfo.environment["BONSAI_SWIFTUI_INPUT_FIXTURE_OUTPUT"] {
      try expected.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("swift_\(name).hex"),
        atomically: true, encoding: .utf8)
    } else {
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let path = root.appendingPathComponent("protocol/generated/fixtures/swift_\(name).hex")
      #expect(try String(contentsOf: path, encoding: .utf8) == expected)
    }
  }

  @Test func invalidEnvironmentSamplesLeaveAdmittedInputIntact() throws {
    let valid = SwiftInputFixtures.environment
    var queue = NativeEventQueue()
    let admitted = queue.append(SwiftInputFixtures.environmentEvent(valid))
    #expect(admitted)
    for field in [
      \NativeHostEnvironment.viewportWidth, \.viewportHeight, \.devicePixelRatio, \.textScale,
      \.safeArea.left, \.safeArea.top, \.safeArea.right, \.safeArea.bottom,
      \.keyboardInsets.left, \.keyboardInsets.top, \.keyboardInsets.right, \.keyboardInsets.bottom,
    ] {
      for number in [Double.nan, Double.infinity, -Double.infinity] {
        var value = valid
        value[keyPath: field] = number
        let accepted = queue.append(SwiftInputFixtures.environmentEvent(value, sequence: 5))
        #expect(!accepted)
        #expect(queue.events.map(\.payload) == [.environmentChanged(valid)])
      }
    }
    for field in [
      \NativeHostEnvironment.viewportWidth, \.viewportHeight, \.devicePixelRatio, \.textScale,
    ] {
      var value = valid
      value[keyPath: field] = -1
      #expect(throws: WireError.invalidHeader) {
        try EventBatch.encode(epoch: 31, events: [SwiftInputFixtures.environmentEvent(value)])
      }
    }
    for field in [\NativeHostEnvironment.devicePixelRatio, \.textScale] {
      var value = valid
      value[keyPath: field] = 0
      #expect(throws: WireError.invalidHeader) {
        try EventBatch.encode(epoch: 31, events: [SwiftInputFixtures.environmentEvent(value)])
      }
    }
    var zero = valid
    zero.viewportWidth = 0
    zero.viewportHeight = 0
    zero.safeArea.left = -1
    let bytes = try EventBatch.encode(
      epoch: 31, events: [SwiftInputFixtures.environmentEvent(zero)])
    #expect(!bytes.isEmpty)
  }
}
