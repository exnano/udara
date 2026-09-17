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
    @Bindable var store: AppStore
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Air quality, quietly close", systemImage: "wind").font(.headline)
                    Text("Udara by Exnano").font(.subheadline.weight(.medium))
                    Text(version).foregroundStyle(.secondary)
                    paragraph("PM2.5 air quality from monitoring stations, close at hand in your menu bar.")
                }

                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Menu bar").font(.subheadline.bold())
                    Picker("Menu bar icon", selection: Binding(
                        get: { store.menuBarIconStyle },
                        set: { style in Task { await store.setMenuBarIconStyle(style) } }
                    )) {
                        ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("menuBarIconStyle")
                    paragraph("Shows your current location when a reading is available. Otherwise, shows the highest available category severity among your saved cities.")
                    LabeledContent("Update checks", value: "Every 10 minutes")
                }

                Divider()
                aboutSection("Readings and freshness") {
                    paragraph("DOE Malaysia is the preferred source for Malaysian locations. Open-Meteo provides model estimates elsewhere and is the fallback when DOE has no usable nearby reading.")
                    paragraph("Values are PM2.5 indices, labeled with their source scale. Malaysian API and estimated US AQI are not directly interchangeable; saved cities are grouped by scale and sorted from high to low within each group.")
                    paragraph("DOE observed time identifies the station reading; readings older than two hours are unavailable. Open-Meteo forecast validity identifies the estimated hour, not the model run age. Estimates expire at the next hour. Missing PM2.5 is never replaced with overall AQI.")
                    paragraph("Where supplied by DOE, PM2.5 concentration is shown separately in µg/m³ as a 24-hour mean. A nearby station may not reflect conditions at your exact location.")
                }

                Divider()
                aboutSection("Privacy") {
                    paragraph("Saved cities and preferences stay on this Mac. Station readings are held in memory. City searches go to Open-Meteo; coordinates and country go to the Udara backend to retrieve readings from DOE or Open-Meteo.")
                    paragraph("GPS location is optional and requires macOS permission. Approximate coordinates are sent to Apple to resolve your area and country. You can use saved cities without enabling location access.")
                }

                Divider()
                aboutSection("Data and attribution") {
                    paragraph("Readings are provided by DOE Malaysia. Estimated forecasts are provided by Open-Meteo and CAMS; they are model-derived, not station observations.")
                    Link("Department of Environment Malaysia", destination: URL(string: "https://eqms.doe.gov.my/")!)
                    Link("Open-Meteo · CAMS data and terms", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                    Link("Open-Meteo · city search", destination: URL(string: "https://open-meteo.com/en/docs/geocoding-api")!)
                }

                Divider()
                aboutSection("Updates and support") {
                    paragraph("Udara is free for non-commercial use. Install updates through Homebrew or download a replacement DMG from GitHub Releases.")
                    Link("Releases", destination: URL(string: "https://github.com/exnano/udara/releases")!)
                    Link("Report an issue", destination: URL(string: "https://github.com/exnano/udara/issues")!)
                    Link("Source code", destination: URL(string: "https://github.com/exnano/udara")!)
                }
            }
            .font(.caption)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: 360, height: 480)
    }
    private func paragraph(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func aboutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}
