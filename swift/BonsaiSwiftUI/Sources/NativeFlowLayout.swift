import SwiftUI

struct RenderFlow: Equatable, Sendable {
  let spacing: Double
  let lineSpacing: Double
  let alignment: Int

  static func decode(_ reader: inout WireReader) throws -> Self {
    let spacing = try reader.finiteDouble()
    let lineSpacing = try reader.finiteDouble()
    guard spacing >= 0, lineSpacing >= 0 else { throw TreeError.invalidProperties }
    return Self(spacing: spacing, lineSpacing: lineSpacing, alignment: try reader.choice(2))
  }
}

/// A finite, intrinsic-item layout. Lazy collections own windowing separately.
struct NativeFlowLayout: Layout {
  let properties: RenderFlow

  struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }
  struct Plan {
    let rows: [Row]
    let proposals: [ProposedViewSize]
    let widths: [CGFloat]
    let size: CGSize
  }

  private func plan(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Plan {
    guard !subviews.isEmpty else { return Plan(rows: [], proposals: [], widths: [], size: .zero) }
    let limit = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
    var rows: [Row] = []
    var row = Row()
    var proposals: [ProposedViewSize] = []
    var widths: [CGFloat] = []
    for index in subviews.indices {
      let ideal = subviews[index].sizeThatFits(.unspecified)
      let width = limit.map { min($0, ideal.width) } ?? ideal.width
      let childProposal = ProposedViewSize(width: width, height: nil)
      let size = subviews[index].sizeThatFits(childProposal)
      proposals.append(childProposal)
      widths.append(size.width)
      let gap = row.indices.isEmpty ? 0 : CGFloat(properties.spacing)
      if let limit, !row.indices.isEmpty, row.width + gap + size.width > limit {
        rows.append(row)
        row = Row()
      }
      row.width += (row.indices.isEmpty ? 0 : CGFloat(properties.spacing)) + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    rows.append(row)
    let width = max(limit ?? 0, rows.map(\.width).max() ?? 0)
    let height =
      rows.reduce(CGFloat.zero) { $0 + $1.height }
      + CGFloat(rows.count - 1) * CGFloat(properties.lineSpacing)
    return Plan(
      rows: rows, proposals: proposals, widths: widths, size: CGSize(width: width, height: height))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    plan(proposal, subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = plan(proposal, subviews)
    var y = bounds.minY
    for row in result.rows {
      let extra = max(0, bounds.width - row.width)
      var x =
        bounds.minX
        + (properties.alignment == 0 ? 0 : properties.alignment == 1 ? extra / 2 : extra)
      for index in row.indices {
        subviews[index].place(
          at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: result.proposals[index])
        x += result.widths[index] + CGFloat(properties.spacing)
      }
      y += row.height + CGFloat(properties.lineSpacing)
    }
  }
}
