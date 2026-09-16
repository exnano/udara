import SwiftUI

extension AQICategory {
    var color: Color {
        switch self {
        case .good: Color(red: 0.20, green: 0.65, blue: 0.37)
        case .moderate: Color(red: 0.98, green: 0.81, blue: 0.22)
        case .sensitive: Color(red: 1, green: 0.57, blue: 0.22)
        case .unhealthy: Color(red: 0.73, green: 0.16, blue: 0.21)
        case .veryUnhealthy: Color(red: 0.48, green: 0.25, blue: 0.65)
        case .hazardous: Color(red: 0.43, green: 0.09, blue: 0.22)
        }
    }
    var foreground: Color {
        switch self { case .good, .moderate, .sensitive: .black; default: .white }
    }
}
struct AQIBadge: View {
    let reading: AQIReading?
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reading?.category.symbol ?? "minus.circle")
            Text(reading.map { String($0.value) } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .foregroundStyle(reading?.category.foreground ?? .secondary)
        .background(reading?.category.color ?? Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.map { "Estimated PM2.5 AQI \($0.value), \($0.category.title)" } ?? "AQI unavailable")
    }
}

/// Glass belongs to the navigation/action layer; AQI colours stay solid for legibility.
extension EnvironmentValues {
    @Entry var udaraReduceTransparencyOverride: Bool? = nil
}

extension View {
    func udaraGlassChrome() -> some View { modifier(UdaraGlassChrome()) }
    func udaraGlassButton(prominent: Bool = false) -> some View {
        modifier(UdaraGlassButton(prominent: prominent))
    }
}
private struct UdaraGlassChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.udaraReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }
}
private struct UdaraGlassButton: ViewModifier {
    var prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.udaraReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        } else {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        }
    }
}


/// Render icon and number together so MenuBarExtra cannot collapse a Label to icon-only.
@MainActor enum MenuBarGlyph {
    static func image(reading: AQIReading?, style: MenuBarIconStyle) -> NSImage {
        let content = HStack(spacing: 5) {
            Image(systemName: style.symbol(for: reading?.category)).frame(width: 18)
            Text(reading.map { String($0.value) } ?? "—")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.black)
        .fixedSize()
        .frame(height: 22)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2, height: 22))
        image.isTemplate = true
        return image
    }
}

#if DEBUG
#Preview("Menu bar · Udara") { Image(nsImage: MenuBarGlyph.image(reading: AQIReading(74), style: .udara)).padding() }
#Preview("Menu bar · Dynamic") { Image(nsImage: MenuBarGlyph.image(reading: AQIReading(168), style: .dynamic)).padding() }
#Preview("Menu bar · Unavailable") { Image(nsImage: MenuBarGlyph.image(reading: nil, style: .udara)).padding() }
#endif
