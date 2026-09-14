import Foundation
import Observation
import SwiftUI

struct NoticeContent: Equatable, Sendable {
  let message: String
  let actionLabel: String?
  let durationMilliseconds: UInt32

  init(message: String, actionLabel: String?, durationMilliseconds: UInt32) throws {
    let whitespace = CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}")
    guard !message.trimmingCharacters(in: whitespace).isEmpty,
      message.utf8.count <= ProtocolLimits.maxStringBytes, durationMilliseconds > 0,
      actionLabel.map({
        !$0.trimmingCharacters(in: whitespace).isEmpty
          && $0.utf8.count <= ProtocolLimits.maxStringBytes
      }) ?? true
    else { throw WireError.invalidOperation }
    self.message = message
    self.actionLabel = actionLabel
    self.durationMilliseconds = durationMilliseconds
  }
}

struct NoticePresentation: Identifiable, Equatable {
  let id: UUID
  let content: NoticeContent
}

@MainActor @Observable final class NativeNotices {
  enum Reason: UInt8 { case action, dismiss, swipe, timeout }
  private final class Entry {
    let presentation: NoticePresentation
    let continuation: CheckedContinuation<Data, any Error>
    var remaining: Duration
    var presented = false
    var announced = false
    init(_ content: NoticeContent, id: UUID, continuation: CheckedContinuation<Data, any Error>) {
      presentation = NoticePresentation(id: id, content: content)
      self.continuation = continuation
      remaining = .milliseconds(Int64(content.durationMilliseconds))
    }
  }
  private(set) var presentation: NoticePresentation?
  private(set) var active = false
  @ObservationIgnored private var owner: UUID?
  @ObservationIgnored private var entries: [Entry] = []
  @ObservationIgnored private var timer: Task<Void, Never>?
  @ObservationIgnored private var timerStarted: ContinuousClock.Instant?
  @ObservationIgnored private var voiceOver = false
  private let clock = ContinuousClock()

  func attach(owner: UUID) {
    if let current = self.owner, current != owner { cancelAll() }
    self.owner = owner
  }
  func detach(owner: UUID) {
    guard self.owner == owner else { return }
    cancelAll()
    self.owner = nil
  }
  func setActive(_ value: Bool) {
    guard active != value else { return }
    active = value
    reconcileTimer()
  }
  func setVoiceOver(_ value: Bool) {
    guard voiceOver != value else { return }
    voiceOver = value
    reconcileTimer()
  }
  func shown(_ id: UUID, owner: UUID) {
    guard self.owner == owner, let first = entries.first, first.presentation.id == id else {
      return
    }
    first.presented = true
    if !first.announced {
      first.announced = true
      AccessibilityNotification.Announcement(first.presentation.content.message).post()
    }
    reconcileTimer()
  }
  func hidden(_ id: UUID, owner: UUID) {
    guard self.owner == owner, let first = entries.first, first.presentation.id == id else {
      return
    }
    first.presented = false
    reconcileTimer()
  }
  func close(_ id: UUID, reason: Reason, owner: UUID) {
    guard self.owner == owner, active, let first = entries.first,
      first.presented, first.presentation.id == id,
      reason != .action || first.presentation.content.actionLabel != nil
    else { return }
    finish(id, result: .success(Data([reason.rawValue])))
  }
  func enqueue(_ content: NoticeContent) async throws -> Data {
    try Task.checkCancellation()
    guard owner != nil else {
      throw HostServiceError.failed("No notification presenter is mounted")
    }
    guard entries.count < 256 else {
      throw HostServiceError.failed("Too many pending notifications")
    }
    let id = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        entries.append(Entry(content, id: id, continuation: continuation))
        if entries.count == 1 { presentation = entries[0].presentation }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
    }
  }
  private func stopTimer() {
    if let started = timerStarted, let first = entries.first {
      first.remaining = max(.zero, first.remaining - started.duration(to: clock.now))
    }
    timerStarted = nil
    timer?.cancel()
    timer = nil
  }
  private func reconcileTimer() {
    guard owner != nil, active, let first = entries.first, first.presented,
      !(voiceOver && first.presentation.content.actionLabel != nil)
    else {
      stopTimer()
      return
    }
    guard timer == nil else { return }
    timerStarted = clock.now
    let id = first.presentation.id
    let delay = first.remaining
    timer = Task { [weak self] in
      do { try await ContinuousClock().sleep(for: delay) } catch { return }
      guard let self, !Task.isCancelled, entries.first?.presentation.id == id,
        active, entries.first?.presented == true
      else { return }
      finish(id, result: .success(Data([Reason.timeout.rawValue])))
    }
  }
  private func finish(_ id: UUID, result: Result<Data, any Error>) {
    guard let index = entries.firstIndex(where: { $0.presentation.id == id }) else { return }
    if index == 0 { stopTimer() }
    let entry = entries.remove(at: index)
    if index == 0 { presentation = entries.first?.presentation }
    entry.continuation.resume(with: result)
  }
  func cancelAll() {
    stopTimer()
    let pending = entries
    entries = []
    presentation = nil
    for entry in pending { entry.continuation.resume(throwing: CancellationError()) }
  }
}

struct NativeNoticePresenter: ViewModifier {
  let controller: NativeNotices
  @State private var owner = UUID()
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

  private func notice(_ presentation: NoticePresentation) -> some View {
    let content = presentation.content
    let message = Text(content.message).lineLimit(5).fixedSize(horizontal: false, vertical: true)
    let buttons = HStack(spacing: 10) {
      if let action = content.actionLabel {
        Button(action) { controller.close(presentation.id, reason: .action, owner: owner) }
          .buttonStyle(.bordered)
      }
      Button {
        controller.close(presentation.id, reason: .dismiss, owner: owner)
      } label: {
        Image(systemName: "xmark")
      }.buttonStyle(.borderless).accessibilityLabel("Dismiss notification")
    }
    return ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 16) {
        message
        buttons
      }
      VStack(alignment: .leading, spacing: 10) {
        message
        buttons.frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(12)
    .frame(maxWidth: 560)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
    .disabled(!controller.active)
    .simultaneousGesture(
      DragGesture(minimumDistance: 12).onEnded { value in
        if value.translation.height > 40, abs(value.translation.width) < value.translation.height {
          controller.close(presentation.id, reason: .swipe, owner: owner)
        }
      }
    )
    .padding(.horizontal, 12).padding(.vertical, 8)
    .onAppear { controller.shown(presentation.id, owner: owner) }
    .onDisappear { controller.hidden(presentation.id, owner: owner) }
    .id(presentation.id)
  }
  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let presentation = controller.presentation { notice(presentation) }
      }
      .onAppear {
        controller.attach(owner: owner)
        controller.setVoiceOver(voiceOver)
      }
      .onChange(of: voiceOver) { _, value in controller.setVoiceOver(value) }
      .onDisappear { controller.detach(owner: owner) }
  }
}
