import AppKit
import Testing

@testable import BonsaiSwiftUI

private func packet(
  _ code: UInt16, _ text: String = "", type: NSEvent.EventType = .keyDown,
  flags: NSEvent.ModifierFlags = [], repeated: Bool = false
) throws -> NSEvent {
  try #require(
    NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
      context: nil, characters: text, charactersIgnoringModifiers: text,
      isARepeat: repeated, keyCode: code))
}

private func mapped(_ mapper: inout AppKitKeyMapper, _ event: NSEvent) throws -> NativeKey {
  let value = mapper.translate(event)
  return try #require(value)
}

struct NativeKeyMappingTests {
  @Test func nonCharacterKeysUseHidIdentityRegardlessOfPlatformCharacterSpelling() {
    for text in ["", "left", "←", "\u{F702}"] {
      #expect(NativeKeyMapping.logical(characters: text, physical: 0x70050) == 0x180050)
    }
    for usage in [-1, 0, 1, 2, 3, 0x10000] {
      #expect(NativeKeyMapping.keyboardUsage(usage) == 0)
    }
    #expect(NativeKeyMapping.keyboardUsage(4) == 0x70004)
    #expect(NativeKeyMapping.keyboardUsage(0xFFFF) == 0x7FFFF)
  }

  @Test func unicodeLogicalIdentifiersDoNotTruncateGraphemesOrConfuseFunctionKeys() {
    #expect(NativeKeyMapping.logical(characters: "e\u{301}", physical: 0x70008) == 0xE9)
    #expect(NativeKeyMapping.logical(characters: "😀", physical: 0) == 0x1F600)
    #expect(NativeKeyMapping.logical(characters: "👨‍👩‍👧", physical: 0) == 0)
    #expect(NativeKeyMapping.logical(characters: "ab", physical: 0) == 0)
    #expect(NativeKeyMapping.logical(characters: "\u{f702}", physical: 0x70050) == 0x180050)
    #expect(NativeKeyMapping.logical(characters: "", physical: 0) == 0)
  }

  @Test @MainActor func nativePacketsPreservePhysicalKeysRepeatsAndNormalizedModifiers() throws {
    var mapper = AppKitKeyMapper()
    for (type, repeated, action) in [
      (NSEvent.EventType.keyDown, false, NativeKey.Action.down),
      (.keyDown, true, .repeat), (.keyUp, true, .up),
    ] {
      let key = try mapped(
        &mapper,
        packet(
          0, "a", type: type,
          flags: [.control, .command, NSEvent.ModifierFlags(rawValue: 2)], repeated: repeated))
      #expect(key == NativeKey(logical: 97, physical: 0x70004, action: action, modifiers: 0x140000))
    }
    for (code, physical) in [
      (UInt16(123), UInt64(0x70050)), (122, 0x7003A),
      (76, 0x70058), (117, 0x7004C), (10, 0x70064),
      (93, 0x70089), (102, 0x70091), (104, 0x70090),
    ] {
      let key = try mapped(&mapper, packet(code))
      #expect(key.physical == physical)
      #expect(key.logical == 0x110000 + physical)
    }
    let unknown = try mapped(&mapper, packet(0xFFFF))
    #expect(unknown.physical == 0 && unknown.logical == 0)
    let mouse = try #require(
      NSEvent.mouseEvent(
        with: .mouseMoved, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
        clickCount: 0, pressure: 0))
    let ignored = mapper.translate(mouse)
    #expect(ignored == nil)
  }

  @Test @MainActor func shiftUsesTheNativeUnmodifiedLayoutRatherThanShiftedCharacters() throws {
    var mapper = AppKitKeyMapper()
    for (code, text) in [(UInt16(0), "A"), (18, "!")] {
      let event = try packet(code, text, flags: .shift)
      let base = try #require(event.characters(byApplyingModifiers: []))
      let scalar = try #require(base.unicodeScalars.first)
      #expect(base.unicodeScalars.count == 1)
      let key = try mapped(&mapper, event)
      #expect(key.logical == UInt64(scalar.value))
      #expect(key.modifiers == 0x20000)
    }
  }

  @Test @MainActor func heldKeyKeepsItsLogicalIdentityUntilReleaseAndResetClearsIt() throws {
    var mapper = AppKitKeyMapper()
    let down = try mapped(&mapper, packet(0, "q"))
    #expect(down.logical == 113)
    let repeated = try mapped(&mapper, packet(0, "a", repeated: true))
    let up = try mapped(&mapper, packet(0, "a", type: .keyUp))
    #expect(repeated.logical == 113 && up.logical == 113)
    let next = try mapped(&mapper, packet(0, "a"))
    #expect(next.logical == 97)
    mapper.reset()
    let reset = try mapped(&mapper, packet(0, "q", type: .keyUp))
    #expect(reset.logical == 113)
  }

  @Test @MainActor func bothShiftKeysHaveIndependentReleaseEdgesAndResetOwnership() throws {
    var mapper = AppKitKeyMapper()
    for (code, flags, action, physical) in [
      (
        UInt16(56), NSEvent.ModifierFlags(rawValue: 0x20002), NativeKey.Action.down, UInt64(0x700E1)
      ),
      (60, .init(rawValue: 0x20006), .down, 0x700E5),
      (56, .init(rawValue: 0x20004), .up, 0x700E1), (60, [], .up, 0x700E5),
    ] {
      let key = try mapped(&mapper, packet(code, type: .flagsChanged, flags: flags))
      #expect(key.action == action && key.physical == physical)
    }
    _ = mapper.translate(try packet(56, type: .flagsChanged, flags: .init(rawValue: 0x20002)))
    mapper.reset()
    let fresh = try mapped(
      &mapper, packet(56, type: .flagsChanged, flags: .init(rawValue: 0x20002)))
    #expect(fresh.action == .down)
    for (raw, action) in [
      (UInt(0x10080), NativeKey.Action.down), (0x10000, .up),
      (0x80, .down), (0, .up),
    ] {
      let caps = try mapped(&mapper, packet(57, type: .flagsChanged, flags: .init(rawValue: raw)))
      #expect(caps.physical == 0x70039 && caps.action == action)
      #expect(caps.modifiers == UInt32(raw & 0x10000))
    }

  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeAppKitKeyPacketsReachTheActualOcamlHandler() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-keyboard-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var binding: (UInt64, UInt64)?
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let node = try reader.integer(UInt64.self)
        guard try reader.integer(UInt16.self) == NodeKindId.keyboardListener else { continue }
        _ = try reader.integer(UInt8.self)
        _ = try reader.integer(UInt8.self)
        #expect(try reader.integer(UInt16.self) == 1)
        #expect(try reader.integer(UInt16.self) == EventTagId.key)
        binding = (node, try reader.integer(UInt64.self))
      }
      let owner = try #require(binding)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var mapper = AppKitKeyMapper()
      var events: [NativeEvent] = []
      for (type, repeated) in [
        (NSEvent.EventType.keyDown, false), (.keyDown, true),
        (.keyDown, true), (.keyUp, false),
      ] {
        let key = try mapped(
          &mapper,
          packet(
            0, "a", type: type,
            flags: .command, repeated: repeated))
        events.append(
          NativeEvent(
            sequence: UInt64(events.count + 1), displayedRevision: frame.revision,
            nodeID: owner.0, handlerID: owner.1, payload: .key(key)))
      }
      let result = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: frame.epoch, events: events))
      let expected =
        "97:458756:down:1048576;97:458756:repeat:1048576;97:458756:repeat:1048576;97:458756:up:1048576;"
      #expect(result.bytes.range(of: Data(expected.utf8)) != nil)
      try await runtime.acknowledge(result, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
