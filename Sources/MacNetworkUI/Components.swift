import SwiftUI

// Menu-style building blocks modeled on the system Wi-Fi / Control Center menus:
// full-width rows, rounded hover highlight, 8 pt text inset, no cards or borders.

/// Clickable menu row with a rounded hover highlight.
struct MenuRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background {
                if hovering && action != nil {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
            }
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(action != nil ? .isButton : [])
    }
}

/// Plain command row ("IP Settings…") with an optional key hint, like a menu item.
struct CommandRow: View {
    let title: String
    var key: String?
    let action: () -> Void

    var body: some View {
        MenuRow(action: action) {
            Text(title)
            Spacer()
            if let key { Text(key).foregroundStyle(.tertiary) }
        }
        .help(key.map { "\(title) (\($0))" } ?? title)
    }
}

/// Round network glyph: accent-filled when active, neutral otherwise (as in the system menu).
struct CircleIcon: View {
    let symbol: String
    var variableValue: Double?
    var active = false
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol, variableValue: variableValue)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: size, height: size)
            .background(Circle().fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
            .contentTransition(.symbolEffect(.replace))
    }
}

struct MenuSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 5)
    }
}

// MARK: Tabs (CodexBar-style switcher)

/// Equal-width segments with an icon above a small title. Selected: accent fill, white text;
/// others: clear, secondary text, faint hover. Modeled on CodexBar's provider switcher
/// (github.com/steipete/CodexBar, MIT).
struct TabSwitcher<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let symbol: (Tab) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                TabSegment(title: title(tab), symbol: symbol(tab), selected: tab == selection) {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TabSegment: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(height: 13)
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.tint) : hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Grouped settings (System Settings look, sized for the panel)

/// Section title + rounded group with divided rows. Looks like a grouped Form but is a plain
/// VStack, so it sizes to content inside the menu panel (a Form would clip).
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(.quinary)
                // Clip so row dividers cannot run past the rounded edge.
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Separator between rows of a SettingsGroup (inset like System Settings).
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 12) }
}

/// One settings row: label (with optional subtitle) left, control or value right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(title, subtitle: subtitle)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
    }
}

/// Title with an optional caption subtitle for settings rows.
/// Adapted from CodexBar's `SettingsRowLabel` (github.com/steipete/CodexBar, MIT, © 2026 Peter Steinberger).
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(isEnabled ? .primary : .secondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
