import SwiftUI

extension EnvironmentValues {
  @Entry var bonsaiToolbarFocus: ToolbarFocusController? = nil
}

#if os(macOS)
  import AppKit

  @MainActor final class NativeControlAttachment {
    let content: NSView
    private var serial: UInt64 = 0
    private weak var current: NativeControlMount?
    private var disposed = false

    init(_ content: NSView) { self.content = content }
    func makeMount() -> NativeControlMount {
      serial += 1
      return NativeControlMount(owner: self, serial: serial)
    }
    func attach(_ mount: NativeControlMount) {
      guard !disposed, mount.window != nil,
        current?.window == nil || mount.serial >= current!.serial
      else { return }
      current = mount
      if content.superview !== mount {
        content.autoresizingMask = [.width, .height]
        mount.addSubview(content)
      }
      content.frame = mount.bounds
      mount.onMounted?()
    }
    func dispose() {
      disposed = true
      content.removeFromSuperview()
      current = nil
    }
  }

  @MainActor final class NativeControlMount: NSView {
    let owner: NativeControlAttachment
    let serial: UInt64
    var onMounted: (() -> Void)?
    init(owner: NativeControlAttachment, serial: UInt64) {
      self.owner = owner
      self.serial = serial
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { owner.content.intrinsicContentSize }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [owner.content] }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      owner.attach(self)
    }
    override func layout() {
      super.layout()
      owner.attach(self)
    }
  }
#else
  import UIKit

  @MainActor final class NativeControlAttachment {
    let content: UIView
    private var serial: UInt64 = 0
    private weak var current: NativeControlMount?
    private var disposed = false

    init(_ content: UIView) { self.content = content }
    func makeMount() -> NativeControlMount {
      serial += 1
      return NativeControlMount(owner: self, serial: serial)
    }
    func attach(_ mount: NativeControlMount) {
      guard !disposed, mount.window != nil,
        current?.window == nil || mount.serial >= current!.serial
      else { return }
      current = mount
      if content.superview !== mount {
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mount.addSubview(content)
      }
      content.frame = mount.bounds
      mount.onMounted?()
    }
    func dispose() {
      disposed = true
      content.removeFromSuperview()
      current = nil
    }
  }

  @MainActor final class NativeControlMount: UIView {
    let owner: NativeControlAttachment
    let serial: UInt64
    var onMounted: (() -> Void)?
    init(owner: NativeControlAttachment, serial: UInt64) {
      self.owner = owner
      self.serial = serial
      super.init(frame: .zero)
      isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: CGSize { owner.content.intrinsicContentSize }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      owner.attach(self)
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      owner.attach(self)
    }
  }
#endif
