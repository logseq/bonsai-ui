import SwiftUI

enum WeightedSizing: Equatable, Sendable {
  case intrinsic
  case share(weight: Double, fills: Bool)

  var weight: Double? {
    if case .share(let weight, _) = self { return weight }
    return nil
  }
}

struct RenderWeightedStack: Equatable, Sendable {
  let spacing: Double?
  let alignment: Int
  let items: [WeightedSizing]

  static func decode(_ reader: inout WireReader, vertical: Bool) throws -> Self {
    let spacing = try reader.flag() ? reader.finiteDouble() : nil
    let alignment = try reader.choice(vertical ? 2 : 4)
    let count = Int(try reader.integer(UInt32.self))
    guard count <= ProtocolLimits.maxNodes else { throw WireError.limitExceeded }
    var items: [WeightedSizing] = []
    for _ in 0..<count {
      if try reader.flag() {
        let weight = try reader.finiteDouble()
        guard weight > 0 else { throw TreeError.invalidProperties }
        items.append(.share(weight: weight, fills: try reader.flag()))
      } else {
        items.append(.intrinsic)
      }
    }
    return Self(spacing: spacing, alignment: alignment, items: items)
  }
}

private struct WeightedSizingKey: LayoutValueKey {
  static let defaultValue = WeightedSizing.intrinsic
}

protocol WeightedAxis {
  static var vertical: Bool { get }
}

enum WeightedHorizontal: WeightedAxis { static let vertical = false }
enum WeightedVertical: WeightedAxis { static let vertical = true }

private struct WeightedStackLayout<Direction: WeightedAxis>: Layout {
  let spacing: Double?
  let alignment: Int

  static var layoutProperties: LayoutProperties {
    var properties = LayoutProperties()
    properties.stackOrientation = Direction.vertical ? .vertical : .horizontal
    return properties
  }

  struct Plan {
    let dimensions: [ViewDimensions]
    let proposals: [ProposedViewSize]
    let gaps: [CGFloat]
    let size: CGSize
    let crossGuide: CGFloat
  }

  private func cross(_ dimensions: ViewDimensions) -> CGFloat {
    Direction.vertical ? dimensions.width : dimensions.height
  }
  private func main(_ dimensions: ViewDimensions) -> CGFloat {
    Direction.vertical ? dimensions.height : dimensions.width
  }
  private func guide(_ dimensions: ViewDimensions) -> CGFloat {
    if Direction.vertical { return dimensions[nativeHorizontalAlignment(alignment)] }
    return dimensions[nativeVerticalAlignment(alignment)]
  }

  private func plan(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Plan {
    guard !subviews.isEmpty else {
      return Plan(dimensions: [], proposals: [], gaps: [], size: .zero, crossGuide: 0)
    }
    let proposedMain = Direction.vertical ? proposal.height : proposal.width
    let extent = proposedMain.flatMap { $0.isFinite ? max(0, $0) : nil }
    let proposedCross = Direction.vertical ? proposal.width : proposal.height
    let crossExtent = proposedCross.flatMap { $0.isFinite ? max(0, $0) : nil }
    func childProposal(_ main: CGFloat?) -> ProposedViewSize {
      Direction.vertical
        ? ProposedViewSize(width: crossExtent, height: main)
        : ProposedViewSize(width: main, height: crossExtent)
    }
    let sizing = subviews.map { $0[WeightedSizingKey.self] }
    let gaps = subviews.indices.map { index -> CGFloat in
      guard index < subviews.count - 1 else { return 0 }
      return spacing.map { CGFloat($0) }
        ?? subviews[index].spacing.distance(
          to: subviews[index + 1].spacing, along: Direction.vertical ? .vertical : .horizontal)
    }
    var proposals = Array(repeating: childProposal(nil), count: subviews.count)
    var dimensions = subviews.map { $0.dimensions(in: childProposal(nil)) }
    if let extent, let largestWeight = sizing.compactMap(\.weight).max() {
      // Normalize before summing so individually finite large weights cannot
      // overflow their total. Every pass is linear in the materialized children.
      let normalized = sizing.map { ($0.weight ?? 0) / largestWeight }
      let total = normalized.reduce(0, +)
      let fixed = subviews.indices.reduce(CGFloat.zero) { value, index in
        value + (sizing[index].weight == nil ? main(dimensions[index]) : 0)
      }
      let remaining = max(0, extent - fixed - gaps.reduce(0, +))
      for index in subviews.indices where sizing[index].weight != nil {
        let share = remaining * CGFloat(normalized[index] / total)
        proposals[index] = childProposal(share)
        dimensions[index] = subviews[index].dimensions(in: proposals[index])
      }
    }
    let crossGuide = dimensions.map(guide).max() ?? 0
    let crossAfter = dimensions.map { cross($0) - guide($0) }.max() ?? 0
    let mainExtent = max(0, dimensions.reduce(CGFloat.zero) { $0 + main($1) } + gaps.reduce(0, +))
    let crossSize = max(0, crossGuide + crossAfter)
    let size =
      Direction.vertical
      ? CGSize(width: crossSize, height: mainExtent) : CGSize(width: mainExtent, height: crossSize)
    return Plan(
      dimensions: dimensions, proposals: proposals, gaps: gaps, size: size, crossGuide: crossGuide)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    plan(proposal, subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = plan(proposal, subviews)
    var cursor: CGFloat = 0
    for index in subviews.indices {
      let dimensions = result.dimensions[index]
      let crossOffset = result.crossGuide - guide(dimensions)
      let x = Direction.vertical ? crossOffset : cursor
      let y = Direction.vertical ? cursor : crossOffset
      subviews[index].place(
        at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
        proposal: result.proposals[index])
      cursor += main(dimensions) + result.gaps[index]
    }
  }
}

struct NativeWeightedStack: View {
  let node: RenderNodeState
  let properties: RenderWeightedStack
  let vertical: Bool
  let activate: @MainActor (RenderNodeState) -> Void

  @ViewBuilder private func item(_ child: RenderNodeState, _ sizing: WeightedSizing) -> some View {
    let view = NativeNodeView(node: child, activate: activate)
    if case .share(_, true) = sizing {
      if vertical {
        view.frame(minHeight: 0, maxHeight: .infinity)
      } else {
        view.frame(minWidth: 0, maxWidth: .infinity)
      }
    } else {
      view
    }
  }

  private var children: some View {
    ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
      item(child, properties.items[index]).layoutValue(
        key: WeightedSizingKey.self, value: properties.items[index])
    }
  }

  var body: some View {
    if vertical {
      WeightedStackLayout<WeightedVertical>(
        spacing: properties.spacing, alignment: properties.alignment
      ) { children }
    } else {
      WeightedStackLayout<WeightedHorizontal>(
        spacing: properties.spacing, alignment: properties.alignment
      ) { children }
    }
  }
}
