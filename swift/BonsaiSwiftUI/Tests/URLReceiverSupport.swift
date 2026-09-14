import AppKit
import Foundation

@MainActor final class URLReceiverFixture {
  let scheme = "bonsai-url-test-" + UUID().uuidString.lowercased()
  private let directory: URL
  private let bundle: URL
  private let identifier: String
  private let receipt: URL
  private static let register =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  init() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("../../..").standardizedFileURL
    directory = root.appendingPathComponent("_build/validation/url-receivers", isDirectory: true)
      .appendingPathComponent(
        "Bonsai URL receiver " + UUID().uuidString, isDirectory: true)
    bundle = directory.appendingPathComponent("Receiver.app", isDirectory: true)
    identifier = "org.bonsai-swiftui.test.url-receiver." + UUID().uuidString.lowercased()
    receipt = directory.appendingPathComponent("received.json")
    let executable = bundle.appendingPathComponent("Contents/MacOS/Receiver")
    do {
      try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
      let plist: [String: Any] = [
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "Receiver",
        "CFBundleName": "Bonsai URL Receiver", "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "26.0", "LSUIElement": true,
        "BonsaiReceiptPath": receipt.path,
        "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme], "CFBundleTypeRole": "Viewer"]],
      ]
      try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
        to: bundle.appendingPathComponent("Contents/Info.plist"))
      let source = root.appendingPathComponent("native/test/url_receiver.swift")
      try Self.run(
        "/usr/bin/xcrun",
        [
          "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0", source.path,
          "-o", executable.path,
        ])
      try Self.run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
      try Self.run(Self.register, ["-f", bundle.path])
    } catch {
      close()
      throw error
    }
  }

  func url(_ token: String) -> String {
    "\(scheme)://message/\(token)?text=%E6%9C%AC%E5%9C%B0%F0%9F%98%80"
  }

  var received: [String] {
    guard let data = try? Data(contentsOf: receipt) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  func waitUntilRegistered() async throws {
    let probe = URL(string: url("registration"))!
    for _ in 0..<200 {
      if NSWorkspace.shared.urlForApplication(toOpen: probe)?.resolvingSymlinksInPath()
        == bundle.resolvingSymlinksInPath()
      {
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw NSError(
      domain: "URLReceiverFixture", code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: "Launch Services did not resolve the registered test receiver"
      ])
  }

  func waitForCount(_ count: Int) async throws {
    for _ in 0..<200 {
      if received.count == count { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw NSError(
      domain: "URLReceiverFixture", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Expected \(count) native URL deliveries; received \(received)"
      ])
  }

  func close() {
    for application in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) {
      application.forceTerminate()
    }
    try? Self.run(Self.register, ["-u", bundle.path])
    try? FileManager.default.removeItem(at: directory)
  }

  private static func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(
        domain: "URLReceiverFixture", code: Int(process.terminationStatus),
        userInfo: [
          NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)
        ])
    }
  }
}
