import SwiftUI

/// Describes the glass material to apply. Mirrors the visual intent of
/// `GlassEffect` on macOS 26 while remaining available on macOS 14.
enum GlassCompatMaterial {
    /// Translucent clear glass → `.ultraThinMaterial`.
    case clear
    /// Solid frosted glass → `.regularMaterial`.
    case regular
    /// No material (identity).
    case identity
}

extension View {
    /// Applies a native Liquid Glass effect on macOS 26+ and a material
    /// fallback on earlier systems.
    ///
    /// - Parameters:
    ///   - material: The glass style to apply.
    ///   - shape: The shape the material clips to.
    /// - Returns: The modified view.
    @ViewBuilder
    func glassEffectCompat(
        _ material: GlassCompatMaterial = .regular,
        in shape: some Shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectCompatNative(material: material, in: shape)
        } else {
            let background: Material? = switch material {
            case .clear: .ultraThinMaterial
            case .regular: .regularMaterial
            case .identity: nil
            }

            if let background {
                self.background(background, in: shape)
            } else {
                self
            }
        }
    }
}

@available(macOS 26.0, *)
private extension View {
    func glassEffectCompatNative(
        material: GlassCompatMaterial,
        in shape: some Shape
    ) -> some View {
        var glass: Glass
        switch material {
        case .identity:
            glass = .identity
        case .clear:
            glass = .clear
        case .regular:
            glass = .regular
        }

        return self.glassEffect(glass, in: shape)
    }
}
