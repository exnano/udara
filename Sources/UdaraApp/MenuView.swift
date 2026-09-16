import SwiftUI

struct MenuView: View {
    @Bindable var store: AppStore
    @State private var page: Page = .cities
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.udaraReduceTransparencyOverride) private var reduceTransparencyOverride
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    enum Page { case cities, search, settings }
    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "wind").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Udara").font(.title3.bold())
                        Text("Estimated PM2.5 AQI").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if page != .cities {
                        Button("Done") { page = .cities }.keyboardShortcut(.cancelAction).udaraGlassButton()
                    } else {
                        Button { page = .search } label: { Image(systemName: "plus") }
                            .help("Add city").accessibilityLabel("Add city").accessibilityIdentifier("addCity").udaraGlassButton()
                    }
                }.padding(12).udaraGlassChrome()
            }.padding(10)
            Divider()
            switch page {
            case .cities: cities
            case .search: CitySearchView(store: store)
            case .settings: SettingsContent(store: store)
            }
            Divider()
            GlassEffectContainer(spacing: 12) {
                HStack {
                    Button { page = page == .settings ? .cities : .settings } label: { Image(systemName: "gearshape") }
                        .help("Settings and about").accessibilityLabel("Settings").accessibilityIdentifier("settings").udaraGlassButton()
                    Spacer()
                    Link("Open-Meteo · CAMS", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                        .font(.caption2)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q").udaraGlassButton()
                }.padding(12)
            }
        }
        .frame(width: 360)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }
    private var currentLocation: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Current location", systemImage: "location.fill").font(.caption.bold())
                Spacer()
                if store.locationPhase == .located {
                    Button { store.requestLocation?() } label: { Image(systemName: "location") }
                        .accessibilityLabel("Detect current location").udaraGlassButton()
                }
            }.padding(.horizontal, 16).padding(.top, 12)
            if let row = store.currentLocationRow {
                CityRowView(status: row, retry: store.state.retries[-1], removable: false)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    switch store.locationPhase {
                    case .locating:
                        HStack { ProgressView().controlSize(.small); Text("Finding your location…") }
                    case .denied:
                        Text("Location access is off. Enable it in System Settings to see nearby air quality.")
                        Button("Location Settings") { store.requestLocation?() }.udaraGlassButton()
                    case .unavailable:
                        Text("Your location is unavailable right now.")
                        Button("Try again") { store.requestLocation?() }.udaraGlassButton()
                    default:
                        Text("See the air quality where you are.")
                        Button("Enable location") { store.requestLocation?() }.udaraGlassButton()
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(16)
            }
        }.accessibilityIdentifier("currentLocation")
    }
    private var cities: some View {
        VStack(spacing: 0) {
            currentLocation
            Divider()
            if store.rows.isEmpty {
                ContentUnavailableView {
                    Label("A little clarity, city by city", systemImage: "leaf")
                } description: {
                    Text("Keep the air quality of places you care about close at hand.")
                } actions: {
                    Button("Add your first city") { page = .search }.udaraGlassButton(prominent: true)
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
                }.frame(height: min(CGFloat(store.rows.count) * 164, store.currentLocationRow == nil ? 360 : 320))
            }
            if let message = store.startupWarning ?? store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).padding(12).textSelection(.enabled)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isRefreshing ? "Checking forecasts…" : "PM2.5 estimates · hourly updates")
                    if let next = store.nextDownload {
                        Text("Next check \(relativeDate(next, to: store.now))")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(store.isRefreshing).help("Check for due updates; forecasts download hourly with up to one minute of jitter")
                    .accessibilityLabel("Check for updates").accessibilityIdentifier("refresh").udaraGlassButton()
            }.padding(12)
        }
    }
}

struct CityRowView: View {
    let status: CityStatus
    var retry: RetryState? = nil
    var removable = true
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
            }
            Text(status.reading?.category.title ?? "No estimate for this hour")
                .font(.caption.weight(.medium))
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let concentration = status.forecast?.sample(at: status.now)?.pm25Concentration {
                        Text("PM2.5 \(concentration, format: .number.precision(.fractionLength(1))) µg/m³ · hourly estimate")
                    }
                    if status.reading != nil {
                        Text("Forecast for \(hourLabel) · \(timezoneLabel)")
                    }
                    if let forecast = status.forecast {
                        Text(forecast.fetchedAt > status.now ? "Download time is ahead of the system clock" : "Downloaded \(relativeDate(forecast.fetchedAt, to: status.now))")
                    }
                    if status.overdue { Text("Cached forecast · update overdue").foregroundStyle(.orange) }
                    if let retry { Text(retry.message).foregroundStyle(.secondary) }
                }.font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if removable {
                    Menu {
                        Button("Remove city", role: .destructive, action: remove)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Actions for \(status.city.name)")
                    .accessibilityLabel("Actions for \(status.city.name)")
                }
            }
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
