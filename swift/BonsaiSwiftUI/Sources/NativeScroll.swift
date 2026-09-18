import SwiftUI

enum InitialScrollAnchor: Int, Equatable, Sendable {
  case start, end
  func point(vertical: Bool) -> UnitPoint {
    vertical ? UnitPoint(x: 0, y: Double(rawValue)) : UnitPoint(x: Double(rawValue), y: 0)
  }
}

// Give content a finite minimum without replacing its intrinsic scroll extent.
// Weighted stacks can distribute the extra space using their ordinary rules.
private struct ScrollMinimumLayout: Layout {
  let vertical: Bool
  let minimum: CGFloat?
  let crossExtent: CGFloat

  private func plan(_ child: LayoutSubview) -> (
    CGSize, ProposedViewSize
  ) {
    let intrinsicProposal = ProposedViewSize(
      width: vertical ? crossExtent : nil,
      height: vertical ? nil : crossExtent)
    let intrinsic = child.sizeThatFits(intrinsicProposal)
    guard let minimum else { return (intrinsic, intrinsicProposal) }
    let extent = max(minimum, vertical ? intrinsic.height : intrinsic.width)
    let expanded = ProposedViewSize(
      width: vertical ? crossExtent : extent,
      height: vertical ? extent : crossExtent)
    let measured = child.sizeThatFits(expanded)
    return (
      CGSize(
        width: vertical ? measured.width : max(extent, measured.width),
        height: vertical ? max(extent, measured.height) : measured.height), expanded
    )
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    plan(subviews[0]).0
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let (_, childProposal) = plan(subviews[0])
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: childProposal)
  }
}

struct NativeScroll: View {
  let node: RenderNodeState
  let vertical: Bool
  let indicators: Bool
  let fillViewport: Bool
  let initialAnchor: InitialScrollAnchor
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    GeometryReader { geometry in
      ScrollView(vertical ? .vertical : .horizontal, showsIndicators: indicators) {
        ScrollMinimumLayout(
          vertical: vertical,
          minimum: fillViewport ? (vertical ? geometry.size.height : geometry.size.width) : nil,
          crossExtent: vertical ? geometry.size.width : geometry.size.height
        ) {
          NativeNodeView(node: node.children[0], activate: activate)
            .environment(\.bonsaiRefresh, nil)

            .frame(
              maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity,
              alignment: .topLeading)
        }
      }
      .defaultScrollAnchor(initialAnchor.point(vertical: vertical), for: .initialOffset)
      .modifier(
        ScrollPositionRetention(
          vertical: vertical, preserveContentOffset: true, command: node.scrollCommand)
      )
      .modifier(ScrollObservationModifier(observer: node.scrollObserver))
    }
  }
}
