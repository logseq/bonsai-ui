import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct FileDialogPresentation {
  let id: UUID
  let request: HostRequest
  let contentTypes: [UTType]
  let document: NativeExportDocument?
  let suggestedName: String?
  var isShown = true
  var isImport: Bool {
    if case .pickFiles = request { return true }
    return false
  }
  var allowMultiple: Bool {
    if case .pickFiles(_, let multiple) = request { return multiple }
    return false
  }
}

@MainActor @Observable final class NativeFileDialogs {
  private(set) var presentation: FileDialogPresentation?
  @ObservationIgnored private var continuation: CheckedContinuation<Data, any Error>?
  @ObservationIgnored private var importTask: Task<Void, Never>?
  @ObservationIgnored private let imports = NativeFileImports()

  func execute(_ request: HostRequest) async throws -> Data {
    try Task.checkCancellation()
    guard presentation == nil else {
      throw HostServiceError.failed("A file dialog is already open")
    }
    let id = UUID()
    let descriptor: FileDialogPresentation
    switch request {
    case .pickFiles(let extensions, _):
      let types = try extensions.map { value -> UTType in
        guard Self.validName(value), !value.hasPrefix("."),
          let type = UTType(filenameExtension: value, conformingTo: .data)
        else { throw HostServiceError.failed("Invalid file extension") }
        return type
      }
      descriptor = FileDialogPresentation(
        id: id, request: request, contentTypes: types.isEmpty ? [.item] : types,
        document: nil, suggestedName: nil)
    case .saveFile(let name, let data):
      if let name, !Self.validName(name) {
        throw HostServiceError.failed("The suggested file name must be a nonempty basename")
      }
      descriptor = FileDialogPresentation(
        id: id, request: request, contentTypes: [.data],
        document: try NativeExportDocument(data: data), suggestedName: name)
    default: throw HostServiceError.failed("A file request is required")
    }
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        presentation = descriptor
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelPending(id: id) }
    }
  }

  private static func validName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255
      && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
  }

  func setShown(_ shown: Bool, id: UUID) {
    guard presentation?.id == id else { return }
    // SwiftUI can dismiss its binding before delivering the completion callback.
    presentation?.isShown = shown
  }

  func imported(_ result: Result<[URL], any Error>, id: UUID) {
    guard let descriptor = presentation, descriptor.id == id, descriptor.isImport,
      importTask == nil
    else { return }
    switch result {
    case .failure(let error): completeFailure(error, id: id)
    case .success(let urls):
      guard descriptor.allowMultiple || urls.count <= 1 else {
        finish(.failure(HostServiceError.failed("Multiple selection was not requested")), id: id)
        return
      }
      importTask = Task { [weak self] in
        guard let self else { return }
        do {
          let files = try await imports.copy(urls)
          guard presentation?.id == id, !Task.isCancelled else {
            imports.discard(files)
            return
          }
          do {
            var writer = WireWriter()
            writer.integer(UInt32(files.count))
            for file in files { try Self.writeFile(file, to: &writer) }
            guard writer.bytes.count <= ProtocolLimits.maxStringBytes else {
              throw WireError.limitExceeded
            }
            finish(.success(writer.bytes), id: id)
          } catch {
            imports.discard(files)
            finish(.failure(error), id: id)
          }
        } catch { finish(.failure(error), id: id) }
      }
    }
  }

  func exported(_ result: Result<URL, any Error>, id: UUID) {
    guard let descriptor = presentation, descriptor.id == id, !descriptor.isImport else { return }
    switch result {
    case .failure(let error): completeFailure(error, id: id)
    case .success(let url):
      do {
        var writer = WireWriter()
        writer.integer(UInt8(1))
        try Self.writeFile(url, to: &writer)
        guard writer.bytes.count <= ProtocolLimits.maxStringBytes else {
          throw WireError.limitExceeded
        }
        finish(.success(writer.bytes), id: id)
      } catch { finish(.failure(error), id: id) }
    }
  }

  private static func writeFile(_ url: URL, to writer: inout WireWriter) throws {
    guard url.isFileURL else { throw HostServiceError.failed("A local file URL is required") }
    writer.integer(UInt8(1))
    try writer.string(url.path)
    writer.integer(UInt8(0))
  }

  private func completeFailure(_ error: any Error, id: UUID) {
    let native = error as NSError
    if native.domain == NSCocoaErrorDomain && native.code == NSUserCancelledError {
      userCancelled(id: id)
    } else {
      finish(.failure(error), id: id)
    }
  }

  func userCancelled(id: UUID) {
    guard let descriptor = presentation, descriptor.id == id, importTask == nil else { return }
    finish(.success(Data(repeating: 0, count: descriptor.isImport ? 4 : 1)), id: id)
  }

  private func finish(_ result: Result<Data, any Error>, id: UUID) {
    guard presentation?.id == id else { return }
    let pending = continuation
    continuation = nil
    presentation = nil
    importTask = nil
    pending?.resume(with: result)
  }

  func cancelPending(id: UUID? = nil) {
    guard let current = presentation?.id, id == nil || current == id else { return }
    importTask?.cancel()
    finish(.failure(CancellationError()), id: current)
  }

  func reset() {
    cancelPending()
    imports.reset()
  }
}

struct NativeFileDialogPresenter: ViewModifier {
  let controller: NativeFileDialogs

  func body(content: Content) -> some View {
    let descriptor = controller.presentation
    content
      .fileImporter(
        isPresented: binding(descriptor, importing: true),
        allowedContentTypes: descriptor?.contentTypes ?? [.item],
        allowsMultipleSelection: descriptor?.allowMultiple ?? false,
        onCompletion: { result in
          if let id = descriptor?.id { controller.imported(result, id: id) }
        },
        onCancellation: {
          if let id = descriptor?.id { controller.userCancelled(id: id) }
        }
      )
      .fileExporter(
        isPresented: binding(descriptor, importing: false),
        document: descriptor?.document,
        contentTypes: [.data], defaultFilename: descriptor?.suggestedName,
        onCompletion: { result in
          if let id = descriptor?.id { controller.exported(result, id: id) }
        },
        onCancellation: {
          if let id = descriptor?.id { controller.userCancelled(id: id) }
        })
  }

  private func binding(_ descriptor: FileDialogPresentation?, importing: Bool) -> Binding<Bool> {
    Binding(
      get: { descriptor?.isImport == importing && descriptor?.isShown == true },
      set: { shown in
        if let id = descriptor?.id { controller.setShown(shown, id: id) }
      })
  }
}
