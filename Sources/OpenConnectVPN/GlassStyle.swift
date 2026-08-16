import SwiftUI

extension View {
    func vpnGlassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(VPNGlassCardModifier(cornerRadius: cornerRadius))
    }
}

private struct VPNGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            legacy(content)
        }
#else
        legacy(content)
#endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
    }
}

struct VPNPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.96), tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.7)
            }
            .shadow(color: tint.opacity(0.25), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
