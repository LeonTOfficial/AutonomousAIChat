import SwiftUI
import AppKit

private struct TransparentGlassModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var transparentGlassModeEnabled: Bool {
        get { self[TransparentGlassModeKey.self] }
        set { self[TransparentGlassModeKey.self] = newValue }
    }
}

struct WindowAccessor: NSViewRepresentable {
    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var configurationScheduled = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfiguration(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window, coordinator: context.coordinator)
        } else {
            scheduleConfiguration(for: nsView, coordinator: context.coordinator)
        }
    }

    private func scheduleConfiguration(for view: NSView, coordinator: Coordinator) {
        guard !coordinator.configurationScheduled else { return }
        coordinator.configurationScheduled = true
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let coordinator else { return }
            coordinator.configurationScheduled = false
            guard let window = view?.window else { return }
            configure(window, coordinator: coordinator)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        guard coordinator.configuredWindow !== window else { return }
        coordinator.configuredWindow = window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 700, height: 560)
    }
}

struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

extension View {
    /// Stable material for frequently resizing or scrolling content. Native
    /// Liquid Glass can repeatedly rebuild geometry for very tall text views.
    func stableGlass<S: Shape>(
        in shape: S,
        tint: Color = .clear
    ) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background(tint, in: shape)
            .overlay(shape.stroke(.white.opacity(0.13), lineWidth: 0.7))
    }

    @ViewBuilder
    func adaptiveGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }

    func transparentGlassReadabilityPanel(
        cornerRadius: CGFloat = 16,
        enabled: Bool = true
    ) -> some View {
        modifier(TransparentGlassReadabilityModifier(
            cornerRadius: cornerRadius,
            enabled: enabled
        ))
    }
}

private struct TransparentGlassReadabilityModifier: ViewModifier {
    @Environment(\.transparentGlassModeEnabled) private var transparentGlassModeEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if transparentGlassModeEnabled && enabled {
            if reduceTransparency {
                content.background(
                    Color(nsColor: .windowBackgroundColor).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                content.background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            content
        }
    }
}
