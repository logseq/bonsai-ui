import AppKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class FileDialogScene {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled],
    backing: .buffered, defer: false)
  let owner = NSObject()
  let host = NativeWindowHost()
  let session: BonsaiSession

  init() {
    initializeAccessibilityApplication()
    window.isReleasedWhenClosed = false
    window.contentView = NSView()
    window.makeKeyAndOrderFront(nil)
    host.attach(window: window, title: "File Dialog Tests", owner: owner)
    session = BonsaiSession(windowHost: host)
    session.isVisible = true
  }
  func start(entrypoint: String = "native-file-results") async throws {
    host.attach(window: window, title: "File Dialog Tests", owner: owner)
    try await session.start(entrypoint: entrypoint)
    _ = try await session.presented(#require(session.ticket))
  }
  func request(repetitions: Int = 1) async throws -> UUID {
    let button = try #require(
      session.tree.nodes.values.first { $0.bindings[EventTagId.press] != nil })
    for _ in 0..<repetitions { #expect(session.activate(button)) }
    _ = try await session.refresh()
    _ = try await session.presented(#require(session.ticket))
    for _ in 0..<100 where host.fileDialogs.presentation == nil {
      try await Task.sleep(for: .milliseconds(2))
    }
    return try #require(host.fileDialogs.presentation?.id)
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let text) = $0.properties, text.value.hasPrefix("Files:") { return text.value }
      return nil
    }.joined()
  }
  func settle(until condition: () -> Bool) async throws {
    for _ in 0..<300 {
      if condition() { return }
      _ = try await session.refresh()
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      try await Task.sleep(for: .milliseconds(2))
    }
    try #require(condition())
  }
  func close() async {
    await session.close()
    window.orderOut(nil)
    window.close()
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeFileExportCompletionReturnsDestinationThroughActualOcaml()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BonsaiExportCompletionTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("Opaque.bin")
    let scene = FileDialogScene()
    do {
      try await scene.start(entrypoint: "native-file-export")
      let id = try await scene.request()
      let descriptor = try #require(scene.host.fileDialogs.presentation)
      #expect(descriptor.suggestedName == "Opaque.bin")
      let document = try #require(descriptor.document)
      try document.makeFileWrapper().write(
        to: destination, options: .atomic, originalContentsURL: nil)
      // Exercise the native completion boundary; this does not drive the system chooser.
      scene.host.fileDialogs.setShown(false, id: id)
      #expect(scene.host.fileDialogs.presentation?.id == id)
      scene.host.fileDialogs.exported(.success(destination), id: id)
      try await scene.settle { scene.status == "Files: \(destination.path):none" }
      #expect(try Data(contentsOf: destination) == Data([0, 255, 128]))
      let cancelled = try await scene.request()
      scene.host.fileDialogs.userCancelled(id: cancelled)
      scene.host.fileDialogs.exported(.success(destination), id: cancelled)
      try await scene.settle { scene.status == "Files: " }
      await scene.close()
      #expect(try Data(contentsOf: destination) == Data([0, 255, 128]))
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func nativeFileImportCompletionCopiesAllFilesThroughActualOcaml() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BonsaiFileDialogTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first.bin")
    let second = root.appendingPathComponent("second.bin")
    let bytes = Data([0, 255, 128])
    try bytes.write(to: first)
    try Data().write(to: second)
    let scene = FileDialogScene()
    do {
      try await scene.start()
      let id = try await scene.request()
      scene.host.fileDialogs.imported(.success([first, second]), id: id)
      try await scene.settle {
        scene.status.contains("first.bin:none|") && scene.status.hasSuffix("second.bin:none")
      }
      let paths = scene.status.dropFirst("Files: ".count).components(separatedBy: "|").map {
        String($0.dropLast(":none".count))
      }
      try #require(paths.count == 2)
      #expect(try Data(contentsOf: URL(fileURLWithPath: paths[0])) == bytes)
      #expect(try Data(contentsOf: URL(fileURLWithPath: paths[1])) == Data())
      #expect(paths != [first.path, second.path])
      await scene.close()
      #expect(paths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
      #expect(try Data(contentsOf: first) == bytes)
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func fileDialogCancellationDoesNotReplaceAnotherRequestOrCrossRestart()
    async throws
  {
    let scene = FileDialogScene()
    do {
      try await scene.start()
      let first = try await scene.request(repetitions: 2)
      try await scene.settle { scene.status == "Files: error" }
      #expect(scene.host.fileDialogs.presentation?.id == first)
      scene.host.fileDialogs.userCancelled(id: first)
      try await scene.settle { scene.status == "Files: " }
      let old = try await scene.request()
      await scene.session.close()
      try await scene.start()
      let current = try await scene.request()
      #expect(old != current)
      scene.host.fileDialogs.userCancelled(id: old)
      scene.host.fileDialogs.imported(.success([]), id: old)
      #expect(scene.host.fileDialogs.presentation?.id == current)
      scene.host.fileDialogs.userCancelled(id: current)
      try await scene.settle { scene.status == "Files: " }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}
