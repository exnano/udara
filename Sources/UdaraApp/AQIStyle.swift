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
        .accessibilityLabel(reading.map { "Estimated US AQI \($0.value), \($0.category.title)" } ?? "AQI unavailable")
    }
}
