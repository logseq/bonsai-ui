import Foundation

@MainActor final class PointerContactIdentities {
  static let shared = PointerContactIdentities()
  private let identities = NSMapTable<AnyObject, NSNumber>(
    keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
  private var nextID: UInt64 = 2

  fileprivate func id(for contact: AnyObject, kind: NativePointer.Kind) -> UInt64 {
    switch kind {
    case .mouse: return 0
    case .stylus, .invertedStylus: return 1
    default: break
    }
    if let existing = identities.object(forKey: contact) { return existing.uint64Value }
    precondition(nextID <= UInt64(Int64.max), "Contact identity space exhausted")
    let id = nextID
    nextID += 1
    identities.setObject(NSNumber(value: id), forKey: contact)
    return id
  }
}

@MainActor final class PointerContactInput {
  struct Sample {
    let id: UInt64
    let kind: NativePointer.Kind
    let position: CGPoint
    let buttons: UInt32
    let generation: UInt64
    let isDown: Bool
    func payload(local: CGPoint, global: CGPoint) -> NativeEventPayload {
      let pointer = NativePointer(
        id: id, localX: local.x, localY: local.y, globalX: global.x, globalY: global.y,
        kind: kind, buttons: buttons)
      return isDown ? .pointerDown(pointer) : .pointerUp(pointer)
    }
  }
  private struct Contact {
    let object: AnyObject
    let id: UInt64
    let kind: NativePointer.Kind
    let generation: UInt64

    func sample(position: CGPoint, buttons: UInt32, isDown: Bool) -> Sample {
      Sample(
        id: id, kind: kind, position: position, buttons: buttons,
        generation: generation, isDown: isDown)
    }
  }
  private let identities: PointerContactIdentities
  private var contacts: [ObjectIdentifier: Contact] = [:]
  private var pending: [(AnyObject, Sample)] = []

  init(identities: PointerContactIdentities = .shared) { self.identities = identities }
  var hasActiveContacts: Bool { !contacts.isEmpty }

  func begin(
    _ contact: AnyObject, kind: NativePointer.Kind, position: CGPoint,
    buttons: UInt32, generation: UInt64
  ) {
    let key = ObjectIdentifier(contact)
    guard contacts[key] == nil else { return }
    let value = Contact(
      object: contact, id: identities.id(for: contact, kind: kind),
      kind: kind, generation: generation)
    contacts[key] = value
    pending.append((contact, value.sample(position: position, buttons: buttons, isDown: true)))
  }

  func end(_ contact: AnyObject, position: CGPoint, buttons: UInt32) {
    guard let value = contacts.removeValue(forKey: ObjectIdentifier(contact)) else { return }
    pending.append((contact, value.sample(position: position, buttons: buttons, isDown: false)))
  }

  func cancel(_ contact: AnyObject) {
    contacts.removeValue(forKey: ObjectIdentifier(contact))
    pending.removeAll { $0.0 === contact }
  }

  func reset() {
    contacts.removeAll()
    pending.removeAll()
  }

  func drain() -> [Sample] {
    let samples = pending.map(\.1)
    pending.removeAll(keepingCapacity: true)
    return samples
  }
}
