import SwiftUI

// MARK: - Segmented Pill Picker
/// Grid of capsule segments; selected one gets accent fill.
/// Unselected uses plain color (no material — material hurts resize perf).

struct SegmentedPillPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var label: (Item) -> String
    var tint: Color = .accentColor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    let isSelected = item == selection

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = item
                        }
                    } label: {
                        Text(label(item))
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? tint : .secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(tint.opacity(0.2))
                                        .overlay(
                                            Capsule()
                                                .stroke(tint.opacity(0.3), lineWidth: 0.5)
                                        )
                                } else {
                                    Capsule()
                                        .fill(.quaternary)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Tab Bar (navigation, not selection)

struct TabBar: View {
    let tabs: [String]
    @Binding var selection: String
    var icons: [String: String] = [:]
    var tint: Color = .accentColor
    // Shared geometry so the underline SLIDES between tabs instead of
    // vanishing from one and appearing in the next.
    @Namespace private var indicatorSpace
    @State private var hoveredTab: String?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = tab == selection
                let isHovered = hoveredTab == tab

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85, blendDuration: 0)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            if let symbol = icons[tab] {
                                Image(systemName: symbol)
                                    .font(.caption.weight(isSelected ? .semibold : .medium))
                            }
                            Text(tab)
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? tint : (isHovered ? .primary : .secondary))
                        .padding(.top, 4)
                        // Single underline per selection via matchedGeometry:
                        // only the selected tab hosts the capsule, the
                        // geometry effect slides it between hosts without
                        // needing multiple competing sources.
                        Color.clear
                            .frame(height: 2.5)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Capsule()
                                        .fill(tint)
                                        .frame(height: 2.5)
                                        .matchedGeometryEffect(id: "tab-underline", in: indicatorSpace)
                                }
                            }
                    }
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHovered && !isSelected ? Color.primary.opacity(0.05) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .onHover { hovered in
                    hoveredTab = hovered ? tab : (hoveredTab == tab ? nil : hoveredTab)
                }
            }
        }
        .focusSection()
    }
}

// MARK: - Segmented Pill Row (action buttons)

struct SegmentedPillRow: View {
    let segments: [(label: String, action: () -> Void, isHighlighted: Bool)]
    var tint: Color = .accentColor
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            ForEach(segments.indices, id: \.self) { index in
                let seg = segments[index]

                Button(action: seg.action) {
                    Text(seg.label)
                        .font(compact ? .caption.weight(seg.isHighlighted ? .semibold : .medium) : .callout.weight(seg.isHighlighted ? .semibold : .medium))
                        .foregroundStyle(seg.isHighlighted ? tint : .secondary)
                        .padding(.horizontal, compact ? 10 : 14)
                        .padding(.vertical, compact ? 4 : 6)
                        .background {
                            if seg.isHighlighted {
                                Capsule()
                                    .fill(tint.opacity(0.2))
                                    .overlay(
                                        Capsule()
                                            .stroke(tint.opacity(0.3), lineWidth: 0.5)
                                    )
                            } else {
                                Capsule()
                                    .fill(.quaternary)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .tracking(0.8)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Card Container

struct RatCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }
}

// MARK: - Section Card

struct RatSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        RatCard {
            SectionHeader(title: title)
            content
        }
    }
}
