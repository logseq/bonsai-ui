import SwiftUI

private struct ScrollMeasurement: Equatable {
  let visible: CGRect
  let content: CGSize
}

// Keep logical leading offsets when native RTL layout changes its physical origin.
// Lazy sections retain their own keyed content anchors; only their viewport resize
// needs point correction. Ordinary content also retains its offset on size changes.
struct ScrollPositionRetention: ViewModifier {
  let vertical: Bool
  let preserveContentOffset: Bool
  var command: NativeScrollCommand? = nil
  @State private var position = ScrollPosition(idType: Never.self)
  @State private var userIsScrolling = false

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .modifier(NativeScrollCommandModifier(controller: command, position: $position))
      .onScrollPhaseChange { _, phase in
        userIsScrolling = phase == .interacting || phase == .decelerating
      }
      .onChange(of: vertical) { _, _ in position = ScrollPosition(idType: Never.self) }
      .onScrollGeometryChange(for: ScrollMeasurement.self) { geometry in
        ScrollMeasurement(visible: geometry.visibleRect, content: geometry.contentSize)
      } action: { previous, next in
        let previousExtent = vertical ? previous.visible.height : previous.visible.width
        let nextExtent = vertical ? next.visible.height : next.visible.width
        let previousContent = vertical ? previous.content.height : previous.content.width
        let nextContent = vertical ? next.content.height : next.content.width
        guard !userIsScrolling, previousExtent > 0, nextExtent > 0,
          previousExtent != nextExtent || (preserveContentOffset && previousContent != nextContent)
        else { return }
        let previousOffset = vertical ? previous.visible.minY : previous.visible.minX
        let target = min(max(0, previousOffset), max(0, nextContent - nextExtent))
        if vertical { position.scrollTo(y: target) } else { position.scrollTo(x: target) }
      }
  }
}
