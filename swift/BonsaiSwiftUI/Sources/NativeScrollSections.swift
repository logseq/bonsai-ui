import SwiftUI

struct RenderScrollSections: Equatable, Sendable {
  let vertical: Bool
  let pinHeaders: Bool
  let pinFooters: Bool
  let spacing: Double
  let indicators: Bool
  var initialAnchor: InitialScrollAnchor = .start

  static func decode(_ reader: inout WireReader) throws -> Self {
    let vertical = try reader.flag()
    let headers = try reader.flag()
    let footers = try reader.flag()
    let spacing = try reader.finiteDouble()
    let indicators = try reader.flag()
    guard spacing >= 0 else { throw TreeError.invalidProperties }
    return Self(
      vertical: vertical, pinHeaders: headers, pinFooters: footers,
      spacing: spacing, indicators: indicators,
      initialAnchor: InitialScrollAnchor(rawValue: try reader.choice(1))!)
  }

  var pinnedViews: PinnedScrollableViews {
    var result: PinnedScrollableViews = []
    if pinHeaders { result.insert(.sectionHeaders) }
    if pinFooters { result.insert(.sectionFooters) }
    return result
  }
}

struct RenderScrollSection: Equatable, Sendable {
  let hasHeader: Bool
  let hasFooter: Bool
  let heroHeight: Double?
  let stretch: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let header = try reader.flag()
    let footer = try reader.flag()
    let height = try reader.flag() ? reader.finiteDouble() : nil
    let stretch = try reader.flag()
    if let height {
      guard height > 0, !header, !footer else { throw TreeError.invalidProperties }
    } else if stretch {
      throw TreeError.invalidProperties
    }
    return Self(hasHeader: header, hasFooter: footer, heroHeight: height, stretch: stretch)
  }
}

struct NativeScrollSections: View {
  let node: RenderNodeState
  let properties: RenderScrollSections
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @ViewBuilder private func section(_ node: RenderNodeState) -> some View {
    if case .scrollSection(let section) = node.properties {
      if let height = section.heroHeight {
        let stretches = section.stretch && !reduceMotion
        NativeNodeView(node: node.children[2], activate: activate)
          .frame(maxWidth: .infinity)
          .frame(height: height)
          .visualEffect { content, geometry in
            let delta =
              stretches
              ? max(0, geometry.frame(in: .scrollView(axis: .vertical)).minY) : 0
            return content.scaleEffect(x: 1, y: (height + delta) / height, anchor: .bottom)
          }
      } else {
        Section {
          ForEach(Array(node.children.dropFirst(2))) { item in
            NativeNodeView(node: item, activate: activate)
          }
        } header: {
          if section.hasHeader { NativeNodeView(node: node.children[0], activate: activate) }
        } footer: {
          if section.hasFooter { NativeNodeView(node: node.children[1], activate: activate) }
        }
      }
    }
  }

  var body: some View {
    ScrollView(properties.vertical ? .vertical : .horizontal) {
      if properties.vertical {
        LazyVStack(
          alignment: .leading, spacing: properties.spacing,
          pinnedViews: properties.pinnedViews
        ) {
          ForEach(node.children) { section($0) }
            .environment(\.bonsaiRefresh, nil)

        }.frame(maxWidth: .infinity, alignment: .leading)
      } else {
        LazyHStack(
          alignment: .top, spacing: properties.spacing,
          pinnedViews: properties.pinnedViews
        ) {
          ForEach(node.children) { section($0) }
            .environment(\.bonsaiRefresh, nil)

        }.frame(maxHeight: .infinity, alignment: .top)
      }
    }.scrollIndicators(properties.indicators ? .visible : .hidden)
      .defaultScrollAnchor(
        properties.initialAnchor.point(vertical: properties.vertical), for: .initialOffset
      )
      .modifier(
        ScrollPositionRetention(
          vertical: properties.vertical, preserveContentOffset: false, command: node.scrollCommand)
      )
      .modifier(RefreshScrollModifier())
      .modifier(ScrollObservationModifier(observer: node.scrollObserver))
  }
}
