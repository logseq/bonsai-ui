import Foundation
import Observation
import SwiftUI

struct HostMenuItem: Equatable, Sendable {
  let id: String
  let label: String
  let enabled: Bool
  var identity: Data { Data(id.utf8) }
}

struct HostMenuContent: Equatable, Sendable {
  let items: [HostMenuItem]
  init(items: [HostMenuItem]) throws {
    let whitespace = CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}")
    var identities = Set<Data>()
    guard !items.isEmpty, items.count <= 1024,
      items.allSatisfy({
        !$0.id.isEmpty && $0.id.utf8.count <= ProtocolLimits.maxStringBytes - 5
          && identities.insert($0.identity).inserted
          && !$0.label.trimmingCharacters(in: whitespace).isEmpty
          && $0.label.utf8.count <= ProtocolLimits.maxStringBytes
      })
    else { throw WireError.invalidOperation }
    self.items = items
  }
}

enum HostDialogContent {
  case menu(HostMenuContent)
  case picker(HostPickerContent)
}

struct HostDialogPresentation: Identifiable {
  let id: UUID
  let content: HostDialogContent
  var isShown = true
}

/// One ephemeral chooser bound to the mounted application, completed after native dismissal.
@MainActor @Observable final class NativeHostDialogs {
  private(set) var presentation: HostDialogPresentation?
  var blocksBackgroundInput: Bool { presentation != nil }
  @ObservationIgnored var onModalChange: (() -> Void)?
  @ObservationIgnored private var owner: UUID?
  @ObservationIgnored private var active = false
  @ObservationIgnored private var nativeVisible = false
  @ObservationIgnored private var continuation: CheckedContinuation<Data, any Error>?
  @ObservationIgnored private var result: Result<Data, any Error>?

  func attach(owner: UUID) {
    if self.owner != owner { cancelAll() }
    self.owner = owner
  }
  func detach(owner: UUID) {
    guard self.owner == owner else { return }
    cancelAll()
    self.owner = nil
  }
  func setActive(_ active: Bool) {
    self.active = active
    if !active, let id = presentation?.id { cancel(id) }
  }
  func execute(_ content: HostDialogContent) async throws -> Data {
    try Task.checkCancellation()
    guard owner != nil, active else {
      throw HostServiceError.failed("No active dialog presenter is mounted")
    }
    guard presentation == nil else {
      throw HostServiceError.failed("A dialog is already open")
    }
    let id = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        presentation = HostDialogPresentation(id: id, content: content)
        onModalChange?()
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel(id) }
    }
  }
  func shown(_ id: UUID, owner: UUID) {
    guard self.owner == owner, presentation?.id == id else { return }
    nativeVisible = true
  }
  func select(_ item: String?, id: UUID, owner: UUID) {
    guard self.owner == owner, active, nativeVisible,
      let presentation, presentation.id == id, presentation.isShown, result == nil
    else { return }
    guard case .menu(let content) = presentation.content else { return }
    if let item,
      !content.items.contains(where: { $0.id.utf8.elementsEqual(item.utf8) && $0.enabled })
    {
      return
    }
    do {
      var writer = WireWriter()
      writer.integer(UInt8(item == nil ? 0 : 1))
      if let item { try writer.string(item) }
      dismiss(id, result: .success(writer.bytes))
    } catch { dismiss(id, result: .failure(error)) }
  }
  func selectPicker(_ value: HostPickerContent?, id: UUID, owner: UUID) {
    guard self.owner == owner, active, nativeVisible,
      let presentation, presentation.id == id, presentation.isShown, result == nil,
      case .picker(let content) = presentation.content
    else { return }
    do {
      dismiss(id, result: .success(try value.map { try content.response($0) } ?? Data([0])))
    } catch { dismiss(id, result: .failure(error)) }
  }
  func dismissByUser(_ id: UUID, owner: UUID) {
    guard self.owner == owner, presentation?.id == id else { return }
    dismiss(id, result: .success(Data([0])))
  }
  func dismissed(_ id: UUID, owner: UUID) {
    guard self.owner == owner, presentation?.id == id else { return }
    finish(id, result: result ?? .success(Data([0])))
  }
  private func dismiss(_ id: UUID, result: Result<Data, any Error>) {
    guard presentation?.id == id, self.result == nil else { return }
    self.result = result
    presentation?.isShown = false
    if !nativeVisible { finish(id, result: result) }
  }
  private func cancel(_ id: UUID) { dismiss(id, result: .failure(CancellationError())) }
  private func finish(_ id: UUID, result: Result<Data, any Error>) {
    guard presentation?.id == id else { return }
    let pending = continuation
    continuation = nil
    self.result = nil
    presentation = nil
    nativeVisible = false
    onModalChange?()
    pending?.resume(with: result)
  }
  func cancelAll() {
    if let id = presentation?.id { finish(id, result: .failure(CancellationError())) }
  }
}

struct NativeHostDialogPresenter: ViewModifier {
  let controller: NativeHostDialogs
  @State private var owner = UUID()

  func body(content: Content) -> some View {
    let descriptor = controller.presentation
    content
      .disabled(controller.blocksBackgroundInput)
      .sheet(
        isPresented: Binding(
          get: {
            descriptor?.id == controller.presentation?.id
              && controller.presentation?.isShown == true
          },
          set: { shown in
            if !shown, let id = descriptor?.id { controller.dismissByUser(id, owner: owner) }
          }),
        onDismiss: {
          if let id = descriptor?.id { controller.dismissed(id, owner: owner) }
        }
      ) {
        if let descriptor {
          Group {
            switch descriptor.content {
            case .menu(let menu):
              VStack(spacing: 12) {
                Text("Actions").font(.headline)
                List(menu.items, id: \.identity) { item in
                  Button {
                    controller.select(item.id, id: descriptor.id, owner: owner)
                  } label: {
                    Text(item.label).frame(maxWidth: .infinity, alignment: .leading)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain).disabled(!item.enabled)
                }
                .listStyle(.plain)
                HStack {
                  Spacer()
                  Button("Cancel", role: .cancel) {
                    controller.select(nil, id: descriptor.id, owner: owner)
                  }.keyboardShortcut(.cancelAction)
                }
              }
              .padding(16)
              .frame(
                minWidth: 240, idealWidth: 320, maxWidth: 340,
                minHeight: 200, idealHeight: 320, maxHeight: 400
              )
            case .picker(let picker):
              NativeHostPickerForm(initial: picker) { value in
                controller.selectPicker(value, id: descriptor.id, owner: owner)
              }.id(descriptor.id)
            }
          }
          .presentationSizing(.fitted)
          .disabled(false)
          .onAppear { controller.shown(descriptor.id, owner: owner) }
        }
      }
      .onAppear { controller.attach(owner: owner) }
      .onDisappear { controller.detach(owner: owner) }
  }
}
