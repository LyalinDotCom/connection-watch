import SwiftUI

struct ModernMacButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tintColor: Color = .accentColor

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderStroke(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.01 : 1.0))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundFill(isPressed: Bool) -> AnyShapeStyle {
        if prominent {
            if isPressed {
                return AnyShapeStyle(tintColor.opacity(0.85))
            }
            return AnyShapeStyle(isHovered ? tintColor.opacity(0.95) : tintColor)
        } else {
            if isPressed {
                return AnyShapeStyle(Color.primary.opacity(0.14))
            }
            return AnyShapeStyle(isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.04))
        }
    }

    private func borderStroke(isPressed: Bool) -> Color {
        if prominent {
            return Color.white.opacity(isHovered ? 0.28 : 0.15)
        }
        return Color.primary.opacity(isHovered ? 0.18 : 0.08)
    }
}

struct ModernIconButtonStyle: ButtonStyle {
    var active: Bool = false
    var activeColor: Color = .accentColor

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .foregroundStyle(active ? activeColor : (isHovered ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.15)
                            : (isHovered ? Color.primary.opacity(0.09) : (active ? activeColor.opacity(0.12) : Color.primary.opacity(0.03)))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        active
                            ? activeColor.opacity(0.3)
                            : Color.primary.opacity(isHovered ? 0.16 : 0.06),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct HoverableCardModifier: ViewModifier {
    var accentColor: Color = .accentColor
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isHovered
                            ? Color(nsColor: .controlBackgroundColor).opacity(0.85)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.5)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isHovered ? accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverableCard(accentColor: Color = .accentColor) -> some View {
        modifier(HoverableCardModifier(accentColor: accentColor))
    }
}
