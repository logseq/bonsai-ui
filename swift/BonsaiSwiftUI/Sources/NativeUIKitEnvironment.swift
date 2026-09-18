#if os(iOS)
  import SwiftUI
  import UIKit

  private struct UIKitWindowGeometry {
    let size: CGSize
    let safeArea: NativeHostEnvironment.Insets
    let keyboard: NativeHostEnvironment.Insets
  }

  /// A transparent window child measures full-window geometry independently of
  /// SwiftUI's keyboard-avoiding layout. Its own guide leaves other views' guides untouched.
  private final class UIKitWindowGeometryView: UIView {
    var onChange: ((UIKitWindowGeometry) -> Void)?
    private var generation = UUID()
    private var scheduled = false
    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      accessibilityElementsHidden = true
      backgroundColor = .clear
      autoresizingMask = [.flexibleWidth, .flexibleHeight]
      keyboardLayoutGuide.followsUndockedKeyboard = true
      keyboardLayoutGuide.usesBottomSafeArea = false
      let tracker = UIView()
      tracker.isUserInteractionEnabled = false
      tracker.accessibilityElementsHidden = true
      tracker.translatesAutoresizingMaskIntoConstraints = false
      addSubview(tracker)
      NSLayoutConstraint.activate([
        tracker.leadingAnchor.constraint(equalTo: keyboardLayoutGuide.leadingAnchor),
        tracker.trailingAnchor.constraint(equalTo: keyboardLayoutGuide.trailingAnchor),
        tracker.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        tracker.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.bottomAnchor),
      ])
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
      super.layoutSubviews()
      schedule()
    }
    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      schedule()
    }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      schedule()
    }

    func invalidate() {
      generation = UUID()
      scheduled = false
      onChange = nil
      removeFromSuperview()
    }
    func schedule() {
      guard !scheduled, let window, onChange != nil else { return }
      scheduled = true
      let generation = self.generation
      Task { @MainActor [weak self, weak window] in
        guard let self, self.generation == generation else { return }
        self.scheduled = false
        guard let window, self.window === window,
          let keyboard = try? NativeKeyboardOcclusion.insets(
            viewport: self.bounds, occlusion: self.keyboardLayoutGuide.layoutFrame)
        else { return }
        let safe = window.safeAreaInsets
        self.onChange?(
          UIKitWindowGeometry(
            size: self.bounds.size,
            safeArea: .init(left: safe.left, top: safe.top, right: safe.right, bottom: safe.bottom),
            keyboard: keyboard))
      }
    }
  }

  final class UIKitEnvironmentAttachmentView: UIView {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
      self.notificationCenter = notificationCenter
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    private weak var session: BonsaiSession?
    private var source: UUID?
    private var preferences: NativeHostEnvironment?
    private var observer: UIKitWindowGeometryView?
    private var registered = false
    private weak var observedScene: UIWindowScene?

    func configure(session: BonsaiSession, source: UUID, preferences: NativeHostEnvironment) {
      if self.session !== session || self.source != source { detach() }
      self.session = session
      self.source = source
      self.preferences = preferences
      isUserInteractionEnabled = false
      accessibilityElementsHidden = true
      attach()
      observer?.schedule()
    }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if observer?.window !== window { detach() }
      attach()
    }
    private func attach() {
      guard observer == nil, let window, session != nil, source != nil else { return }
      observedScene = window.windowScene
      session?.isActive = observedScene?.activationState == .foregroundActive
      if let observedScene {
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.didDisconnectNotification] {
          notificationCenter.addObserver(self, selector: #selector(sceneActivationChanged(_:)),
            name: name, object: observedScene)
        }
      }
      let observer = UIKitWindowGeometryView(frame: window.bounds)
      self.observer = observer
      observer.onChange = { [weak self, weak observer] geometry in
        guard let self, let observer, self.observer === observer,
          observer.window === self.window, let session = self.session,
          let source = self.source, var sample = self.preferences
        else { return }
        sample.viewportWidth = geometry.size.width
        sample.viewportHeight = geometry.size.height
        sample.orientation = geometry.size.width > geometry.size.height ? .landscape : .portrait
        sample.safeArea = geometry.safeArea
        sample.keyboardInsets = geometry.keyboard
        if self.registered {
          session.observeEnvironment(sample, source: source)
        } else {
          self.registered = true
          session.beginEnvironmentObservation(source: source, sample: sample)
        }
      }
      window.insertSubview(observer, at: 0)
      observer.setNeedsLayout()
      observer.schedule()
    }
    @objc private func sceneActivationChanged(_ notification: Notification) {
      guard let scene = notification.object as? UIWindowScene,
        scene === observedScene, scene === window?.windowScene else { return }
      session?.isActive = notification.name == UIScene.didActivateNotification
    }

    private func detach() {
      notificationCenter.removeObserver(self)
      observedScene = nil
      session?.isActive = false
      observer?.invalidate()
      observer = nil
      if registered, let source { session?.endEnvironmentObservation(source: source) }
      registered = false
    }
    func invalidate() {
      detach()
      session = nil
      source = nil
      preferences = nil
    }
  }

  struct NativeUIKitEnvironmentProbe: UIViewRepresentable {
    let session: BonsaiSession
    let source: UUID
    let preferences: NativeHostEnvironment
    func makeUIView(context: Context) -> UIKitEnvironmentAttachmentView {
      let view = UIKitEnvironmentAttachmentView()
      view.configure(session: session, source: source, preferences: preferences)
      return view
    }
    func updateUIView(_ view: UIKitEnvironmentAttachmentView, context: Context) {
      view.configure(session: session, source: source, preferences: preferences)
    }
    static func dismantleUIView(_ view: UIKitEnvironmentAttachmentView, coordinator: ()) {
      view.invalidate()
    }
  }
#endif
