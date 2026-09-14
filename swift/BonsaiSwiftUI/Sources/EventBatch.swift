import Foundation

enum NativeEventPayload: Equatable, Sendable {
  case nativeView(NativeViewEmission)
  case civilDate(CivilDate)
  case civilTime(CivilTime)
  case press
  case key(NativeKey)
  case environmentChanged(NativeHostEnvironment)
  case tap(NativeTap)
  case doubleTap(NativeTap)
  case longPress
  case pointerEnter(NativePointer)
  case pointerLeave(NativePointer)
  case pointerDown(NativePointer)
  case pointerUp(NativePointer)
  case animationCompleted(UInt64)
  case hostResponse(HostResponse)
  case applicationResponse(UInt64, Data)
  case applicationRequestError(UInt64, BonsaiApplicationError)
  case applicationEvent(Data)
  case sliderChanged(Double)
  case sliderEnded(Double)
  case rangeSliderChanged(Double, Double)
  case rangeSliderEnded(Double, Double)
  case valueChanged(Bool)
  case scroll(pixels: Double, delta: Double)
  case removalRequested(token: Int64, direction: Int64)
  case removalCompleted(Int64)
  case refreshRequest(Int64)
  case scrollPosition(Int64)
  case tableSort(Int64, Bool)
  case tableSelection(Int64, Bool)
  case menuAction(Int64)
  case pickerSelection(Int64)
  case navigationPath([String])
  case tabSelection(RenderTabKey)
  case navigationSplit(RenderSplitState)
  case semanticsAction(UInt64)
  case textEdit(TextEdit)
  case textSubmit(String)
  case focusChanged(Bool)
  case textLimitReached
  case visibleRange(Range<Int>)

  var isRuntimeControl: Bool {
    switch self {
    case .hostResponse, .applicationResponse, .applicationRequestError, .applicationEvent,
      .environmentChanged:
      true
    default: false
    }
  }

  var isApplicationReply: Bool {
    switch self {
    case .applicationResponse, .applicationRequestError: true
    default: false
    }
  }

  var owningApplicationBytes: NativeEventPayload {
    func copy(_ data: Data) -> Data {
      data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return Data() }
        return Data(bytes: base, count: bytes.count)
      }
    }
    switch self {
    case .applicationResponse(let id, let bytes): return .applicationResponse(id, copy(bytes))
    case .applicationEvent(let bytes): return .applicationEvent(copy(bytes))
    default: return self
    }
  }

  var hoverPointer: NativePointer? {
    switch self {
    case .pointerEnter(let pointer), .pointerLeave(let pointer): pointer
    default: nil
    }
  }

  var sliderSelection: SliderSelection? {
    switch self {
    case .sliderChanged(let value), .sliderEnded(let value):
      return SliderSelection(lower: value, upper: nil)
    case .rangeSliderChanged(let lower, let upper), .rangeSliderEnded(let lower, let upper):
      return SliderSelection(lower: lower, upper: upper)
    default: return nil
    }
  }
  var tag: Int {
    switch self {
    case .nativeView: EventTagId.nativeEvent
    case .civilDate: EventTagId.civilDateChanged
    case .civilTime: EventTagId.civilTimeChanged
    case .pointerEnter: EventTagId.pointerEnter
    case .pointerLeave: EventTagId.pointerLeave
    case .pointerDown: EventTagId.pointerDown
    case .pointerUp: EventTagId.pointerUp
    case .semanticsAction: EventTagId.semanticsAction
    case .tabSelection: EventTagId.tabSelected
    case .navigationSplit: EventTagId.navigationSplitChanged
    case .navigationPath: EventTagId.navigationPathChanged
    case .sliderChanged: EventTagId.sliderChanged
    case .sliderEnded: EventTagId.sliderChangeEnd
    case .rangeSliderChanged: EventTagId.rangeSliderChanged
    case .rangeSliderEnded: EventTagId.rangeSliderChangeEnd
    case .valueChanged: EventTagId.valueChanged
    case .scroll: EventTagId.scrollNotification
    case .removalRequested: EventTagId.removalRequested
    case .removalCompleted: EventTagId.removalCompleted
    case .refreshRequest: EventTagId.refreshRequest
    case .scrollPosition: EventTagId.scrollPositionChanged
    case .tableSort: EventTagId.tableSortRequested
    case .tableSelection: EventTagId.tableRowSelected
    case .menuAction: EventTagId.menuAction
    case .pickerSelection: EventTagId.pickerSelected
    case .animationCompleted: EventTagId.animationCompleted
    case .tap: EventTagId.tap
    case .doubleTap: EventTagId.doubleTap
    case .longPress: EventTagId.longPress
    case .press: EventTagId.press
    case .key: EventTagId.key
    case .environmentChanged: EventTagId.environmentChanged
    case .hostResponse: EventTagId.hostResponse
    case .applicationResponse: EventTagId.applicationResponse
    case .applicationRequestError: EventTagId.applicationRequestError
    case .applicationEvent: EventTagId.applicationEvent
    case .textEdit: EventTagId.textEdit
    case .textSubmit: EventTagId.textSubmit
    case .focusChanged: EventTagId.focusChanged
    case .textLimitReached: EventTagId.textLimitReached
    case .visibleRange: EventTagId.visibleRangeChanged
    }
  }
}

struct NativeEvent: Sendable {
  let sequence: UInt64
  let displayedRevision: UInt64
  let nodeID: UInt64
  let handlerID: UInt64
  var payload: NativeEventPayload = .press
}

enum EventBatch {
  static func encode(epoch: UInt64, events: [NativeEvent]) throws -> Data {
    guard epoch > 0, epoch <= UInt64(Int64.max) else { throw WireError.invalidHeader }
    guard events.count <= ProtocolLimits.maxOperations,
      events.count <= (ProtocolLimits.maxFrameBytes - ProtocolLimits.headerBytes - 4) / 38
    else { throw WireError.limitExceeded }
    var previous: UInt64 = 0
    var body = WireWriter()
    body.integer(UInt32(events.count))
    for event in events {
      guard
        [event.sequence, event.displayedRevision]
          .allSatisfy({ $0 > 0 && $0 <= UInt64(Int64.max) })
      else { throw WireError.invalidHeader }
      if event.payload.isRuntimeControl {
        guard event.nodeID == 0, event.handlerID == 0 else { throw WireError.invalidHeader }
      } else {
        guard [event.nodeID, event.handlerID].allSatisfy({ $0 > 0 && $0 <= UInt64(Int64.max) })
        else {
          throw WireError.invalidHeader
        }
      }
      guard event.sequence > previous else { throw WireError.invalidOrder }
      previous = event.sequence
      var record = WireWriter()
      record.integer(event.sequence)
      record.integer(event.displayedRevision)
      record.integer(event.nodeID)
      record.integer(event.handlerID)
      record.integer(UInt16(event.payload.tag))
      switch event.payload {
      case .environmentChanged(let environment): try environment.encode(into: &record)
      case .key(let key):
        guard key.logical <= UInt64(Int64.max), key.physical <= UInt64(Int64.max) else {
          throw WireError.invalidHeader
        }
        record.integer(key.logical)
        record.integer(key.physical)
        record.integer(key.action.rawValue)
        record.integer(key.modifiers)
      case .applicationResponse(let id, let bytes):
        guard id > 0, id <= UInt64(Int64.max) else { throw WireError.invalidHeader }
        guard bytes.count <= ProtocolLimits.maxApplicationPayloadBytes else {
          throw WireError.limitExceeded
        }
        record.integer(id)
        record.integer(UInt32(bytes.count))
        record.bytes.append(bytes)
      case .applicationRequestError(let id, let failure):
        guard id > 0, id <= UInt64(Int64.max) else { throw WireError.invalidHeader }
        guard failure.message.utf8.count <= 4096 else { throw WireError.limitExceeded }
        record.integer(id)
        record.integer(failure.code)
        try record.string(failure.message)
      case .applicationEvent(let bytes):
        guard bytes.count <= ProtocolLimits.maxApplicationPayloadBytes else {
          throw WireError.limitExceeded
        }
        record.integer(UInt32(bytes.count))
        record.bytes.append(bytes)
      case .tap(let tap), .doubleTap(let tap):
        guard tap.isValid else { throw WireError.invalidHeader }
        record.integer(tap.localX.bitPattern)
        record.integer(tap.localY.bitPattern)
        record.integer(tap.globalX.bitPattern)
        record.integer(tap.globalY.bitPattern)
        record.integer(tap.kind.rawValue)
      case .nativeView(let value):
        guard value.kind > 0, value.kind <= 65535, value.version > 0, value.event > 0 else {
          throw WireError.invalidHeader
        }
        guard value.payload.count < ProtocolLimits.maxFrameBytes else {
          throw WireError.limitExceeded
        }
        record.integer(value.kind)
        record.integer(value.version)
        record.integer(value.event)
        record.integer(UInt32(value.payload.count))
        record.bytes.append(value.payload)
      case .civilDate(let value):
        guard value.isValid else { throw WireError.invalidHeader }
        record.integer(UInt16(value.year))
        record.integer(UInt8(value.month))
        record.integer(UInt8(value.day))
      case .civilTime(let value):
        guard value.isValid else { throw WireError.invalidHeader }
        record.integer(UInt8(value.hour))
        record.integer(UInt8(value.minute))
      case .pointerEnter(let pointer), .pointerLeave(let pointer), .pointerDown(let pointer),
        .pointerUp(let pointer):
        guard pointer.isValid else { throw WireError.invalidHeader }
        record.integer(pointer.id)
        record.integer(pointer.localX.bitPattern)
        record.integer(pointer.localY.bitPattern)
        record.integer(pointer.globalX.bitPattern)
        record.integer(pointer.globalY.bitPattern)
        record.integer(pointer.kind.rawValue)
        record.integer(pointer.buttons)
      case .animationCompleted(let id):
        guard id <= UInt64(Int64.max) else { throw WireError.invalidHeader }
        record.integer(id)
      case .scroll(let pixels, let delta):
        guard pixels.isFinite, delta.isFinite else { throw WireError.invalidHeader }
        record.integer(pixels.bitPattern)
        record.integer(delta.bitPattern)
      case .removalRequested(let token, let direction):
        record.integer(token)
        record.integer(direction)
      case .removalCompleted(let token): record.integer(token)
      case .refreshRequest(let token): record.integer(token)
      case .scrollPosition(let id): record.integer(id)
      case .tableSort(let id, let value), .tableSelection(let id, let value):
        record.integer(id)
        record.integer(UInt8(value ? 1 : 0))
      case .menuAction(let id): record.integer(id)
      case .pickerSelection(let value): record.integer(value)
      case .hostResponse(let response):
        guard response.requestID > 0, response.requestID <= UInt64(Int64.max),
          response.value.count <= ProtocolLimits.maxStringBytes,
          response.status != .cancelled || response.value.isEmpty
        else { throw WireError.invalidHeader }
        record.integer(response.requestID)
        record.integer(response.status.rawValue)
        record.integer(UInt32(response.value.count))
        record.bytes.append(response.value)
      case .sliderChanged(let value), .sliderEnded(let value):
        guard value.isFinite else { throw WireError.invalidHeader }
        record.integer(value.bitPattern)
      case .rangeSliderChanged(let lower, let upper), .rangeSliderEnded(let lower, let upper):
        guard lower.isFinite, upper.isFinite, lower <= upper else { throw WireError.invalidHeader }
        record.integer(lower.bitPattern)
        record.integer(upper.bitPattern)
      case .tabSelection(let key):
        guard !key.value.isEmpty else { throw WireError.invalidHeader }
        try record.string(key.value)
      case .navigationSplit(let state):
        guard state.isValid else { throw WireError.invalidHeader }
        record.integer(UInt8(state.visibility))
        record.integer(UInt8(state.compactColumn))
        record.integer(UInt8(state.selectionKey == nil ? 0 : 1))
        if let key = state.selectionKey { try record.string(key) }
      case .navigationPath(let keys):
        guard keys.count <= 256, keys.allSatisfy({ !$0.isEmpty }),
          Set(keys.map { Data($0.utf8) }).count == keys.count
        else { throw WireError.invalidHeader }
        record.integer(UInt32(keys.count))
        for key in keys { try record.string(key) }
      case .semanticsAction(let id):
        guard id > 0, id <= UInt64(Int64.max) else { throw WireError.invalidHeader }
        record.integer(id)
      case .visibleRange(let range):
        guard range.lowerBound >= 0 else { throw WireError.invalidHeader }
        record.integer(UInt64(range.lowerBound))
        record.integer(UInt64(range.upperBound))
      case .press, .longPress, .textLimitReached: break
      case .valueChanged(let value): record.integer(UInt8(value ? 1 : 0))
      case .focusChanged(let focused): record.integer(UInt8(focused ? 1 : 0))
      case .textSubmit(let text): try record.string(text)
      case .textEdit(let edit):
        guard
          [edit.sessionID, edit.localRevision, edit.baseDocumentRevision]
            .allSatisfy({ $0 <= UInt64(Int64.max) })
        else { throw TextSessionError.invalidRevision }
        record.integer(edit.sessionID)
        record.integer(edit.localRevision)
        record.integer(edit.baseDocumentRevision)
        try record.string(edit.value.text)
        record.textRange(edit.value.selection)
        record.integer(UInt8(edit.value.marked == nil ? 0 : 1))
        if let marked = edit.value.marked { record.textRange(marked) }
      }
      guard
        body.bytes.count + 4 + record.bytes.count <= ProtocolLimits.maxFrameBytes
          - ProtocolLimits.headerBytes
      else { throw WireError.limitExceeded }
      body.integer(UInt32(record.bytes.count))
      body.bytes.append(record.bytes)
    }
    var writer = WireWriter()
    writer.bytes.append(contentsOf: "BSFR".utf8)
    writer.integer(UInt16(ProtocolVersion.protocolMajor))
    writer.integer(UInt16(ProtocolVersion.protocolMinor))
    writer.integer(UInt16(ProtocolLimits.headerBytes))
    writer.integer(UInt8(FrameKindId.eventBatch))
    writer.integer(UInt8(0))
    writer.integer(epoch)
    writer.integer(events.first?.displayedRevision ?? 0)
    writer.integer(events.last?.sequence ?? 0)
    writer.integer(UInt32(body.bytes.count))
    writer.integer(UInt32(0))
    writer.integer(UInt32(0))
    writer.bytes.append(body.bytes)
    return writer.bytes
  }
}

struct WireWriter {
  var bytes = Data()

  mutating func integer<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
  }

  mutating func string(_ value: String) throws {
    let count = value.utf8.count
    guard count <= ProtocolLimits.maxStringBytes else { throw WireError.limitExceeded }
    integer(UInt32(count))
    bytes.append(contentsOf: value.utf8)
  }

  mutating func textRange(_ range: NSRange) {
    integer(UInt32(range.location))
    integer(UInt32(range.location + range.length))
  }
}
