import SwiftUI

struct MenuView: View {
    @Bindable var store: AppStore
    @State private var page: Page = .cities
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    enum Page { case cities, search, settings }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wind").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Udara").font(.title3.bold())
                    Text("Estimated US AQI").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if page != .cities {
                    Button("Done") { page = .cities }.keyboardShortcut(.cancelAction)
                } else {
                    Button { page = .search } label: { Image(systemName: "plus") }
                        .help("Add city").accessibilityLabel("Add city").accessibilityIdentifier("addCity")
                }
            }.padding(16)
            Divider()
            switch page {
            case .cities: cities
            case .search: CitySearchView(store: store)
            case .settings: SettingsContent()
            }
            Divider()
            HStack {
                Button { page = page == .settings ? .cities : .settings } label: { Image(systemName: "gearshape") }
                    .help("Settings and about").accessibilityLabel("Settings").accessibilityIdentifier("settings")
                Spacer()
                Link("Open-Meteo · CAMS", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                    .font(.caption2)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.borderless).padding(12)
        }
        .frame(width: 360)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }
    private var cities: some View {
        VStack(spacing: 0) {
            if store.rows.isEmpty {
                ContentUnavailableView {
                    Label("A little clarity, city by city", systemImage: "leaf")
                } description: {
                    Text("Keep the air quality of places you care about close at hand.")
                } actions: {
                    Button("Add your first city") { page = .search }.buttonStyle(.borderedProminent)
                }.padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.rows) { row in
                            CityRowView(status: row, retry: store.state.retries[row.id]) {
                                Task { await store.remove(row.city) }
                            }
                            if row.id != store.rows.last?.id { Divider().padding(.horizontal, 16) }
                        }
                    }
                }.frame(height: min(CGFloat(store.rows.count) * 142, 520))
            }
            if let message = store.startupWarning ?? store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).padding(12).textSelection(.enabled)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isRefreshing ? "Checking forecasts…" : "Hourly estimates · daily downloads")
                    if let next = store.nextDownload {
                        Text("Next check \(relativeDate(next, to: store.now))")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(store.isRefreshing).help("Check for due updates; cached forecasts are kept for 24 hours")
                    .accessibilityLabel("Check for updates").accessibilityIdentifier("refresh")
            }.padding(12)
        }
    }
}

struct CityRowView: View {
    let status: CityStatus
    var retry: RetryState? = nil
    var remove: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.city.name).font(.headline).lineLimit(2)
                    Text(status.city.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                AQIBadge(reading: status.reading)
                Menu {
                    Button("Remove city", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 18)
                    .accessibilityLabel("Actions for \(status.city.name)")
            }
            Text(status.reading?.category.title ?? "No estimate for this hour")
                .font(.caption.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                if status.reading != nil {
                    Text("Forecast for \(hourLabel) · \(timezoneLabel)")
                }
                if let forecast = status.forecast {
                    Text(forecast.fetchedAt > status.now ? "Download time is ahead of the system clock" : "Downloaded \(relativeDate(forecast.fetchedAt, to: status.now))")
                }
                if status.overdue { Text("Cached forecast · update overdue").foregroundStyle(.orange) }
                if let retry { Text(retry.message).foregroundStyle(.secondary) }
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(16)
        .accessibilityElement(children: .contain)
    }
    private var timezone: TimeZone { TimeZone(identifier: status.city.timezone) ?? .gmt }
    private var hourLabel: String {
        let hour = Date(timeIntervalSince1970: floor(status.now.timeIntervalSince1970 / 3600) * 3600)
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: hour)
    }
    private var timezoneLabel: String { timezone.abbreviation(for: status.now) ?? status.city.timezone }
}

private func relativeDate(_ date: Date, to now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}
