import AppKit
import Observation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class HostEnvironmentSettings {
  var phase: ScenePhase = .active
  var scheme: ColorScheme = .dark
  var locale = Locale(identifier: "zh_CN")
  var bold: LegibilityWeight? = .bold
}

@MainActor private struct EnvironmentTestHost: View {
  let session: BonsaiSession
  let settings: HostEnvironmentSettings
  var body: some View {
    BonsaiApplicationView(entrypoint: "native-environment", session: session)
      .environment(\.scenePhase, settings.phase)
      .environment(\.colorScheme, settings.scheme)
      .environment(\.locale, settings.locale)
      .environment(\.legibilityWeight, settings.bold)
  }
}

@MainActor private func environmentFields(_ session: BonsaiSession) -> [String: String] {
  let text =
    session.tree.nodes.values.compactMap { node -> String? in
      if case .text(let value) = node.properties { return value.value }
      return nil
    }.first ?? ""
  return Dictionary(
    uniqueKeysWithValues: text.split(separator: "|").compactMap {
      let pair = $0.split(separator: "=", maxSplits: 1).map(String.init)
      return pair.count == 2 ? (pair[0], pair[1]) : nil
    })
}

@MainActor private func settleEnvironment(_ host: NSView) async throws {
  for _ in 0..<25 {
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(20))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeHostEnvironmentReachesOCamlAndTracksWindowAndSettings() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    let settings = HostEnvironmentSettings()
    let host = NSHostingView(rootView: EnvironmentTestHost(session: session, settings: settings))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 640, height: 400),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    do {
      try await settleEnvironment(host)
      let first = environmentFields(session)
      #expect(first["platform"] == "macos")
      #expect(first["width"] == "640")
      #expect(first["height"] == "400")
      #expect(Double(first["scale"] ?? "") == Double(window.backingScaleFactor))
      #expect(Double(first["text"] ?? "") == 1)
      #expect(first["brightness"] == "dark")
      #expect(first["locale"] == "zh-CN")
      #expect(first["safe"] == "0,0,0,0")
      #expect(first["keyboard"] == "0,0,0,0")
      #expect(first["bold"] == "true")
      let workspace = NSWorkspace.shared
      #expect(first["voiceover"] == String(workspace.isVoiceOverEnabled))
      #expect(first["invert"] == String(workspace.accessibilityDisplayShouldInvertColors))
      #expect(first["animations"] == String(workspace.accessibilityDisplayShouldReduceMotion))
      #expect(first["motion"] == String(workspace.accessibilityDisplayShouldReduceMotion))
      #expect(first["contrast"] == String(workspace.accessibilityDisplayShouldIncreaseContrast))
      #expect(first["orientation"] == "landscape")
      #expect(first["pointers"] == "14")
      let unchanged = session.tree.revision
      try await settleEnvironment(host)
      #expect(session.tree.revision == unchanged)

      settings.scheme = .light
      settings.locale = Locale(identifier: "fr_CA")
      settings.bold = nil
      window.setContentSize(NSSize(width: 360, height: 560))
      try await settleEnvironment(host)
      let changed = environmentFields(session)
      #expect(changed["width"] == "360")
      #expect(changed["height"] == "560")
      #expect(changed["orientation"] == "portrait")
      #expect(changed["brightness"] == "light")
      #expect(changed["locale"] == "fr-CA")
      #expect(changed["bold"] == "false")
      for key in ["voiceover", "invert", "animations", "motion", "contrast"] {
        #expect(changed[key] == first[key])
      }
      #expect(session.tree.revision > unchanged)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func nativeHostEnvironmentResumesWithLatestSampleAndResendsAfterRestart()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    let settings = HostEnvironmentSettings()
    for _ in 0..<2 {
      let host = NSHostingView(rootView: EnvironmentTestHost(session: session, settings: settings))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 300),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      do {
        try await settleEnvironment(host)
        #expect(environmentFields(session)["platform"] == "macos")
        settings.phase = .background
        try await settleEnvironment(host)
        let revision = session.tree.revision
        settings.locale = Locale(identifier: "de_DE")
        window.setContentSize(NSSize(width: 700, height: 300))
        settings.locale = Locale(identifier: "ja_JP")
        window.setContentSize(NSSize(width: 800, height: 300))
        try await settleEnvironment(host)
        #expect(session.tree.revision == revision)
        settings.phase = .active
        try await settleEnvironment(host)
        #expect(environmentFields(session)["locale"] == "ja-JP")
        #expect(environmentFields(session)["width"] == "800")
        window.orderOut(nil)
        try await settleEnvironment(host)
        #expect(!session.isVisible)
        let hiddenRevision = session.tree.revision
        settings.locale = Locale(identifier: "en_GB")
        try await settleEnvironment(host)
        #expect(session.tree.revision == hiddenRevision)
        window.orderFront(nil)
        try await settleEnvironment(host)
        #expect(environmentFields(session)["locale"] == "en-GB")
        window.orderOut(nil)
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(50))
        await session.close()
        #expect(session.tree.root == nil)
      } catch {
        window.orderOut(nil)
        window.contentView = nil
        await session.close()
        throw error
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeHostEnvironmentRejectsInvalidAndRetiredSources() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    let first = UUID()
    let second = UUID()
    var value = SwiftInputFixtures.environment
    session.beginEnvironmentObservation(source: first, sample: value)
    do {
      try await session.start(entrypoint: "native-environment")
      #expect(environmentFields(session)["platform"] == "unknown")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(environmentFields(session)["locale"] == "zh-CN")
      let revision = session.tree.revision
      value.locale = "retired-pending"
      session.observeEnvironment(value, source: first)
      var invalid = value
      invalid.viewportWidth = .nan
      session.beginEnvironmentObservation(source: second, sample: invalid)
      #expect(try await session.refresh() == false)
      #expect(session.tree.revision == revision)
      #expect(environmentFields(session)["locale"] == "zh-CN")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }

      value.locale = "de-DE"
      session.observeEnvironment(value, source: second)
      session.endEnvironmentObservation(source: first)
      session.observeEnvironment(SwiftInputFixtures.environment, source: first)
      for field in [
        \NativeHostEnvironment.viewportWidth, \.viewportHeight, \.devicePixelRatio,
        \.textScale, \.safeArea.left, \.keyboardInsets.bottom,
      ] {
        for number in [Double.nan, Double.infinity, -Double.infinity] {
          invalid = value
          invalid[keyPath: field] = number
          session.observeEnvironment(invalid, source: second)
        }
      }
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(environmentFields(session)["locale"] == "de-DE")
      let acceptedRevision = session.tree.revision
      #expect(try await session.refresh() == false)
      #expect(session.tree.revision == acceptedRevision)
      session.endEnvironmentObservation(source: second)
      value.locale = "retired"
      session.observeEnvironment(value, source: second)
      #expect(try await session.refresh() == false)
      await session.close()
      session.observeEnvironment(value, source: second)
      try await session.start(entrypoint: "native-environment")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh() == false)
      #expect(environmentFields(session)["platform"] == "unknown")
      session.beginEnvironmentObservation(source: UUID(), sample: SwiftInputFixtures.environment)
      #expect(try await session.refresh())
      #expect(environmentFields(session)["locale"] == "zh-CN")
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
