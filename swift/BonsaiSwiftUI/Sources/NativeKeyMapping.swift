import Foundation

enum NativeKeyMapping {
  // Physical keys use (HID page << 16) | usage; zero means unknown.
  static func keyboardUsage(_ usage: Int) -> UInt64 {
    (4...0xFFFF).contains(usage) ? 0x70000 | UInt64(usage) : 0
  }

  static func logical(characters: String, physical: UInt64) -> UInt64 {
    if physical >> 16 == 7 {
      switch physical & 0xFFFF {
      case 0x28...0x2B, 0x39...0x53, 0x58, 0x65...0x66, 0x68...0x81,
        0x90...0x98, 0x9E, 0xE0...0xE7:
        return 0x110000 + physical
      default: break
      }
    }
    let scalars = characters.precomposedStringWithCanonicalMapping.unicodeScalars
    guard scalars.count <= 1 else { return 0 }
    if let scalar = scalars.first, scalar.value >= 0x20, scalar.value != 0x7F,
      !(0xF700...0xF747).contains(scalar.value)
    {
      return UInt64(scalar.value)
    }
    guard physical > 0, physical <= UInt64(Int64.max) - 0x110000 else { return 0 }
    return 0x110000 + physical
  }
}

private struct NativeKeyState {
  private var held: [UInt64: UInt64] = [:]
  mutating func reset() { held.removeAll() }
  mutating func key(
    characters: String, physical: UInt64, action: NativeKey.Action,
    modifiers: UInt
  ) -> NativeKey {
    let logical =
      held[physical] ?? NativeKeyMapping.logical(characters: characters, physical: physical)
    if physical != 0 {
      if action == .up { held.removeValue(forKey: physical) } else { held[physical] = logical }
    }
    return NativeKey(
      logical: logical, physical: physical, action: action,
      modifiers: UInt32(modifiers & 0x00FF_0000))
  }
}

#if os(macOS)
  import AppKit
  import Carbon.HIToolbox
  import IOKit.hidsystem

  struct AppKitKeyMapper {
    private var state = NativeKeyState()
    mutating func reset() { state.reset() }
    mutating func translate(_ event: NSEvent) -> NativeKey? {
      guard event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged else {
        return nil
      }
      let physical = Self.physicalKeys[event.keyCode] ?? 0
      let action: NativeKey.Action
      let characters: String
      switch event.type {
      case .keyDown, .keyUp:
        action = event.type == .keyUp ? .up : event.isARepeat ? .repeat : .down
        if !event.modifierFlags.intersection([.shift, .capsLock]).isEmpty {
          // AppKit's charactersIgnoringModifiers retains Shift; UIKit's does not.
          characters = event.characters(byApplyingModifiers: []) ?? ""
        } else {
          characters = event.charactersIgnoringModifiers ?? ""
        }
      case .flagsChanged:
        guard let mask = Self.modifierMasks[event.keyCode] else { return nil }
        action = event.modifierFlags.rawValue & mask != 0 ? .down : .up
        characters = ""
      default: return nil
      }
      return state.key(
        characters: characters, physical: physical, action: action,
        modifiers: event.modifierFlags.rawValue)
    }

    // Device-specific bits distinguish releasing one Shift while the other
    // stays held; aggregate flags cannot determine that edge.
    private static let modifierMasks: [UInt16: UInt] = [
      UInt16(kVK_Control): UInt(NX_DEVICELCTLKEYMASK),
      UInt16(kVK_RightControl): UInt(NX_DEVICERCTLKEYMASK),
      UInt16(kVK_Shift): UInt(NX_DEVICELSHIFTKEYMASK),
      UInt16(kVK_RightShift): UInt(NX_DEVICERSHIFTKEYMASK),
      UInt16(kVK_Option): UInt(NX_DEVICELALTKEYMASK),
      UInt16(kVK_RightOption): UInt(NX_DEVICERALTKEYMASK),
      UInt16(kVK_Command): UInt(NX_DEVICELCMDKEYMASK),
      UInt16(kVK_RightCommand): UInt(NX_DEVICERCMDKEYMASK),
      UInt16(kVK_CapsLock): UInt(NX_DEVICE_ALPHASHIFT_STATELESS_MASK),
      UInt16(kVK_Function): NSEvent.ModifierFlags.function.rawValue,
    ]

    // Carbon virtual positions mapped to USB HID Keyboard/Keypad usages.
    private static let physicalKeys: [UInt16: UInt64] = [
      UInt16(kVK_ANSI_A): 0x70004,
      UInt16(kVK_ANSI_B): 0x70005,
      UInt16(kVK_ANSI_C): 0x70006,
      UInt16(kVK_ANSI_D): 0x70007,
      UInt16(kVK_ANSI_E): 0x70008,
      UInt16(kVK_ANSI_F): 0x70009,
      UInt16(kVK_ANSI_G): 0x7000A,
      UInt16(kVK_ANSI_H): 0x7000B,
      UInt16(kVK_ANSI_I): 0x7000C,
      UInt16(kVK_ANSI_J): 0x7000D,
      UInt16(kVK_ANSI_K): 0x7000E,
      UInt16(kVK_ANSI_L): 0x7000F,
      UInt16(kVK_ANSI_M): 0x70010,
      UInt16(kVK_ANSI_N): 0x70011,
      UInt16(kVK_ANSI_O): 0x70012,
      UInt16(kVK_ANSI_P): 0x70013,
      UInt16(kVK_ANSI_Q): 0x70014,
      UInt16(kVK_ANSI_R): 0x70015,
      UInt16(kVK_ANSI_S): 0x70016,
      UInt16(kVK_ANSI_T): 0x70017,
      UInt16(kVK_ANSI_U): 0x70018,
      UInt16(kVK_ANSI_V): 0x70019,
      UInt16(kVK_ANSI_W): 0x7001A,
      UInt16(kVK_ANSI_X): 0x7001B,
      UInt16(kVK_ANSI_Y): 0x7001C,
      UInt16(kVK_ANSI_Z): 0x7001D,
      UInt16(kVK_ANSI_1): 0x7001E,
      UInt16(kVK_ANSI_2): 0x7001F,
      UInt16(kVK_ANSI_3): 0x70020,
      UInt16(kVK_ANSI_4): 0x70021,
      UInt16(kVK_ANSI_5): 0x70022,
      UInt16(kVK_ANSI_6): 0x70023,
      UInt16(kVK_ANSI_7): 0x70024,
      UInt16(kVK_ANSI_8): 0x70025,
      UInt16(kVK_ANSI_9): 0x70026,
      UInt16(kVK_ANSI_0): 0x70027,
      UInt16(kVK_Return): 0x70028,
      UInt16(kVK_Escape): 0x70029,
      UInt16(kVK_Delete): 0x7002A,
      UInt16(kVK_Tab): 0x7002B,
      UInt16(kVK_Space): 0x7002C,
      UInt16(kVK_ANSI_Minus): 0x7002D,
      UInt16(kVK_ANSI_Equal): 0x7002E,
      UInt16(kVK_ANSI_LeftBracket): 0x7002F,
      UInt16(kVK_ANSI_RightBracket): 0x70030,
      UInt16(kVK_ANSI_Backslash): 0x70031,
      UInt16(kVK_ANSI_Semicolon): 0x70033,
      UInt16(kVK_ANSI_Quote): 0x70034,
      UInt16(kVK_ANSI_Grave): 0x70035,
      UInt16(kVK_ANSI_Comma): 0x70036,
      UInt16(kVK_ANSI_Period): 0x70037,
      UInt16(kVK_ANSI_Slash): 0x70038,
      UInt16(kVK_CapsLock): 0x70039,
      UInt16(kVK_F1): 0x7003A,
      UInt16(kVK_F2): 0x7003B,
      UInt16(kVK_F3): 0x7003C,
      UInt16(kVK_F4): 0x7003D,
      UInt16(kVK_F5): 0x7003E,
      UInt16(kVK_F6): 0x7003F,
      UInt16(kVK_F7): 0x70040,
      UInt16(kVK_F8): 0x70041,
      UInt16(kVK_F9): 0x70042,
      UInt16(kVK_F10): 0x70043,
      UInt16(kVK_F11): 0x70044,
      UInt16(kVK_F12): 0x70045,
      UInt16(kVK_Help): 0x70049,
      UInt16(kVK_Home): 0x7004A,
      UInt16(kVK_PageUp): 0x7004B,
      UInt16(kVK_ForwardDelete): 0x7004C,
      UInt16(kVK_End): 0x7004D,
      UInt16(kVK_PageDown): 0x7004E,
      UInt16(kVK_RightArrow): 0x7004F,
      UInt16(kVK_LeftArrow): 0x70050,
      UInt16(kVK_DownArrow): 0x70051,
      UInt16(kVK_UpArrow): 0x70052,
      UInt16(kVK_ANSI_KeypadClear): 0x70053,
      UInt16(kVK_ANSI_KeypadDivide): 0x70054,
      UInt16(kVK_ANSI_KeypadMultiply): 0x70055,
      UInt16(kVK_ANSI_KeypadMinus): 0x70056,
      UInt16(kVK_ANSI_KeypadPlus): 0x70057,
      UInt16(kVK_ANSI_KeypadEnter): 0x70058,
      UInt16(kVK_ANSI_Keypad1): 0x70059,
      UInt16(kVK_ANSI_Keypad2): 0x7005A,
      UInt16(kVK_ANSI_Keypad3): 0x7005B,
      UInt16(kVK_ANSI_Keypad4): 0x7005C,
      UInt16(kVK_ANSI_Keypad5): 0x7005D,
      UInt16(kVK_ANSI_Keypad6): 0x7005E,
      UInt16(kVK_ANSI_Keypad7): 0x7005F,
      UInt16(kVK_ANSI_Keypad8): 0x70060,
      UInt16(kVK_ANSI_Keypad9): 0x70061,
      UInt16(kVK_ANSI_Keypad0): 0x70062,
      UInt16(kVK_ANSI_KeypadDecimal): 0x70063,
      UInt16(kVK_ISO_Section): 0x70064,
      UInt16(kVK_ContextualMenu): 0x70065,
      UInt16(kVK_ANSI_KeypadEquals): 0x70067,
      UInt16(kVK_F13): 0x70068,
      UInt16(kVK_F14): 0x70069,
      UInt16(kVK_F15): 0x7006A,
      UInt16(kVK_F16): 0x7006B,
      UInt16(kVK_F17): 0x7006C,
      UInt16(kVK_F18): 0x7006D,
      UInt16(kVK_F19): 0x7006E,
      UInt16(kVK_F20): 0x7006F,
      UInt16(kVK_Mute): 0x7007F,
      UInt16(kVK_VolumeUp): 0x70080,
      UInt16(kVK_VolumeDown): 0x70081,
      UInt16(kVK_JIS_KeypadComma): 0x70085,
      UInt16(kVK_JIS_Underscore): 0x70087,
      UInt16(kVK_JIS_Yen): 0x70089,
      UInt16(kVK_JIS_Kana): 0x70090,
      UInt16(kVK_JIS_Eisu): 0x70091,
      UInt16(kVK_Control): 0x700E0,
      UInt16(kVK_Shift): 0x700E1,
      UInt16(kVK_Option): 0x700E2,
      UInt16(kVK_Command): 0x700E3,
      UInt16(kVK_RightControl): 0x700E4,
      UInt16(kVK_RightShift): 0x700E5,
      UInt16(kVK_RightOption): 0x700E6,
      UInt16(kVK_RightCommand): 0x700E7,
    ]
  }
#else
  import UIKit

  @MainActor struct UIKitKeyMapper {
    private var state = NativeKeyState()
    mutating func reset() { state.reset() }
    mutating func translate(_ key: UIKey, action: NativeKey.Action) -> NativeKey {
      state.key(
        characters: key.charactersIgnoringModifiers,
        physical: NativeKeyMapping.keyboardUsage(key.keyCode.rawValue),
        action: action, modifiers: UInt(truncatingIfNeeded: key.modifierFlags.rawValue))
    }
  }
#endif
