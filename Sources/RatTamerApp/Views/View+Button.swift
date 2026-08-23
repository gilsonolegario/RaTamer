import SwiftUI

extension View {
    /// Adds hover (macOS) and press effects to a Button's content view.
    /// Provides immediate visual feedback on press for both macOS and iOS.
    /// Includes a minimum visual press duration.
    ///
    /// - Parameters:
    ///   - hoverScale: The scale factor to apply on hover (macOS only,
    ///                 default: 1.2)
    ///   - pressScale: The scale factor to apply when pressed (default: 0.9)
    ///   - minimumPressDuration: The minimum time the press effect should
    ///                           visually last (default: 0.1 seconds)
    /// - Returns: A view with hover and press effects applied.
    func styledButton(
        hoverScale: CGFloat = 1.2,
        pressScale: CGFloat = 0.9,
        minimumPressDuration: TimeInterval = 0.1,
    ) -> some View {
        modifier(StyledButtonModifier(
            hoverScale: hoverScale,
            pressScale: pressScale,
            minimumPressDuration: minimumPressDuration,
        ))
    }
}

/// Custom button style that provides visual press feedback with a minimum
/// duration. Ensures the press effect is visible for at least the specified
/// duration, even for quick clicks.
struct PressedButtonStyle: ButtonStyle {
    let scale: CGFloat
    let minimumDuration: TimeInterval

    @State private var isVisuallyPressed: Bool = false
    @State private var pressEndTask: Task<Void, Never>? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isVisuallyPressed ? scale : 1.0)
            .animation(.interactiveSpring, value: isVisuallyPressed)
            .onChange(of: configuration.isPressed) { _, isPhysicallyPressed in
                if isPhysicallyPressed {
                    pressEndTask?.cancel()
                    pressEndTask = nil

                    if !isVisuallyPressed {
                        isVisuallyPressed = true
                    }
                } else {
                    guard isVisuallyPressed else {
                        return
                    }

                    pressEndTask = Task {
                        do {
                            try await Task.sleep(for: .seconds(minimumDuration))
                            try Task.checkCancellation()

                            isVisuallyPressed = false
                        } catch is CancellationError {
                            // NO-OP
                        } catch {
                            isVisuallyPressed = false
                        }

                        pressEndTask = nil
                    }
                }
            }
            .onAppear {
                if configuration.isPressed, !isVisuallyPressed {
                    isVisuallyPressed = true
                }
            }
            .onDisappear {
                pressEndTask?.cancel()
            }
    }
}

/// View modifier that combines hover and press effects for buttons.
/// On macOS: applies hover scale effect.
private struct StyledButtonModifier: ViewModifier {
    let hoverScale: CGFloat
    let pressScale: CGFloat
    let minimumPressDuration: TimeInterval

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(
                PressedButtonStyle(scale: pressScale,
                                   minimumDuration: minimumPressDuration),
            )
            .scaleEffect(isHovering ? hoverScale : 1.0)
            .animation(.interactiveSpring, value: isHovering)
            .onHover { value in
                isHovering = value
            }
    }
}
