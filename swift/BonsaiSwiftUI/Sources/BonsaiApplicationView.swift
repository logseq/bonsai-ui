import OSLog
import SwiftUI

/// A single-window SwiftUI host for an embedded OCaml/Bonsai application.
public struct BonsaiApplicationView: View {
  private let entrypoint: String
  private let payload: Data
  @State private var session: BonsaiSession
  @State private var failed = false
  @Environment(\.scenePhase) private var scenePhase

  public init(
    entrypoint: String, payload: Data = Data(),
    nativeViews: BonsaiNativeViews = BonsaiNativeViews(),
    applicationBridge: BonsaiApplicationBridge? = nil
  ) {
    self.init(
      entrypoint: entrypoint, payload: payload,
      session: BonsaiSession(nativeViews: nativeViews, applicationBridge: applicationBridge))
  }

  init(entrypoint: String, payload: Data = Data(), session: BonsaiSession) {
    self.entrypoint = entrypoint
    self.payload = payload
    _session = State(initialValue: session)
  }

  public var body: some View {
    Group {
      if let root = session.tree.root, let application = session.application {
        NativeNodeView(node: root, activate: { session.activate($0) })
          .modifier(SwiftUIEnvironmentModifier(values: application.environment))
          .preferredColorScheme(
            application.environment.mode == 1
              ? .light : application.environment.mode == 2 ? .dark : nil)
      } else if failed {
        ContentUnavailableView(
          "Unable to open application", systemImage: "exclamationmark.triangle")
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .modifier(NativeNoticePresenter(controller: session.windowHost.notices))
    .modifier(NativeHostDialogPresenter(controller: session.windowHost.dialogs))
    .coordinateSpace(name: NativeGestureCoordinateSpace.application)
    .background {
      NativeHostEnvironmentObserver(session: session)
    }
    .modifier(NativeLayoutObserver(requests: session.windowHost.layoutRequests))
    .modifier(NativeFileDialogPresenter(controller: session.windowHost.fileDialogs))
    .background(SessionPresentationObserver(session: session, failed: report))
    .onChange(of: scenePhase, initial: true) { _, phase in session.isActive = phase == .active }
    .task {
      let lifetime = UUID()
      do {
        try await session.start(
          entrypoint: entrypoint, payload: payload, lifetimeIdentity: lifetime)
        while !Task.isCancelled && !failed && session.lifetimeIdentity == lifetime {
          try await session.refresh()
          try await Task.sleep(for: .milliseconds(session.isActive && session.isVisible ? 16 : 250))
        }
      } catch is CancellationError {
        // View removal cancels its owned task and closes the native runtime.
      } catch {
        if session.lifetimeIdentity == lifetime { report(error) }
      }
      await session.close(ifCurrent: lifetime)
    }
  }

  private func report(_ error: any Error) {
    Logger(subsystem: "org.bonsai-swiftui", category: "host").error(
      "\(String(describing: error), privacy: .public)")
    failed = true
  }
}

private struct SessionPresentationObserver: View {
  let session: BonsaiSession
  let failed: (any Error) -> Void

  var body: some View {
    PresentationProbe(
      ticket: session.isActive ? session.ticket : nil,
      title: session.application?.title,
      windowHost: session.windowHost,
      onVisibility: { session.isVisible = $0 },
      onPresented: { observed in
        do { return try await session.presented(observed) } catch {
          if session.lifetimeIdentity == observed.session { failed(error) }
          await session.close(ifCurrent: observed.session)
          return false
        }
      })
  }
}
