import SwiftUI

struct CitySearchView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a city").font(.headline)
            TextField("Search city name", text: $query)
                .textFieldStyle(.roundedBorder).focused($focused).accessibilityIdentifier("citySearch")
            if store.isSearching {
                ProgressView("Searching…").controlSize(.small)
            } else if let error = store.searchError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                Text("Enter at least 3 characters. Choose a city by its region and country.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.searchResults.isEmpty {
                Text("No matching cities found.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.searchResults) { city in
                        let saved = store.state.cities.contains { $0.id == city.id }
                        Button { Task { await store.add(city) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(city.name).font(.body.weight(.medium))
                                    Text(city.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(saved ? Color.secondary : Color.teal)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered).disabled(saved)
                        .accessibilityLabel("\(city.name), \(city.subtitle), \(saved ? "already added" : "add city")")
                    }
                }
            }.frame(maxHeight: 300)
        }.padding(16).frame(height: 390)
        .task(id: query) { await store.search(query) }
        .onAppear { focused = true }
    }
}

struct SettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Air quality, quietly close", systemImage: "wind").font(.headline)
            Text("Udara shows model-estimated US AQI. Forecasts may differ from nearby monitoring stations.")
            LabeledContent("Downloads", value: "Every 24 hours")
            LabeledContent("Display", value: "Current hourly estimate")
            Text("Cities and forecasts stay on this Mac. City searches and coordinates are sent to Open-Meteo; its servers receive your IP address. No account or location permission is required.")
            Text("Data: Open-Meteo and CAMS ENSEMBLE / CAMS global forecasts, under the applicable attribution licences. Udara rounds AQI to whole numbers.")
            Link("Data sources and attribution", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
            Link("Open-Meteo terms and licence", destination: URL(string: "https://open-meteo.com/en/terms")!)
            Text("Free, non-commercial use. Updates are installed through Homebrew or a replacement DMG from GitHub Releases.")
            Text("Udara \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .foregroundStyle(.secondary)
        }.font(.caption).padding(16).frame(width: 360)
    }
}
