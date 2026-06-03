import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var location: LocationManager

    let isActive: Bool

    private enum OLEDSection: CaseIterable {
        case time
        case weather
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yy"
        return f
    }()

    private let timeTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let weatherTimer = Timer.publish(every: 600.0, on: .main, in: .common).autoconnect()
    private let oledCycleTimer = Timer.publish(every: 7.0, on: .main, in: .common).autoconnect()

    @State private var currentTime: String = "--:--:--"
    @State private var currentDay: String = "---"

    @State private var searchText: String = "Pomona"
    @State private var currentCity: String = "Pomona"
    @State private var tempText: String = "--°"
    @State private var conditionText: String = "--"
    @State private var hiLoText: String = "H --° L --°"

    @State private var suggestions: [GeoCity] = []
    @State private var currentOLEDSection: OLEDSection = .time

    private let apiKey = "00ce8e9704991fb2c3b2f6bcde173521"

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.16), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    topHeader
                    searchCard
                    weatherCard
                    timeCard
                    Spacer(minLength: 18)
                }
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .foregroundColor(.white)
        .onAppear {
            updateTimeOnly()
            fetchWeather(forQuery: currentCity)
            location.requestPermission()
            location.start()

            if isActive {
                pushActiveOLEDSectionIfNeeded()
            }
        }
        .onReceive(timeTimer) { _ in
            updateTimeOnly()

            // Only push time updates when the Weather/Time page is active
            // and the OLED is currently showing TIME.
            guard isActive, currentOLEDSection == .time else { return }
            sendTimeDataPacket()
        }
        .onReceive(weatherTimer) { _ in
            fetchWeather(forQuery: currentCity)
        }
        .onReceive(oledCycleTimer) { _ in
            guard isActive else { return }
            advanceOLEDSection()
            pushActiveOLEDSectionIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            if active {
                currentOLEDSection = .time
                pushActiveOLEDSectionIfNeeded()
            }
        }
        .onChange(of: ble.isConnected) { _, connected in
            if connected && isActive {
                pushActiveOLEDSectionIfNeeded()
            }
        }
    }
}

// MARK: - UI
private extension ContentView {
    var backgroundGradient: LinearGradient {
        dynamicBackground(condition: conditionText)
    }

    var topHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ARIS")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .kerning(5)

                Capsule()
                    .fill(ble.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: (ble.isConnected ? Color.green : Color.red).opacity(0.7), radius: 8)
            }

            Text("Weather + Time")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: ble.isConnected ? "antenna.radiowaves.left.and.right" : "bolt.slash")
                        .font(.caption)

                    Text(ble.statusText)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .opacity(0.9)

                    Text(location.statusText)
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 18)
    }

    var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.70))

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .opacity(0.9)

                    TextField("City (e.g. Pomona, US)", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _, newValue in
                            fetchSuggestions(for: newValue)
                        }
                        .font(.subheadline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

                Button {
                    fetchWeather(forQuery: searchText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.cyan.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.cyan.opacity(0.35), radius: 14, x: 0, y: 10)
                }
            }

            if !suggestions.isEmpty && searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestions) { city in
                        Button {
                            let display = city.displayName
                            let query = city.queryString
                            searchText = display
                            currentCity = display
                            suggestions = []
                            fetchWeather(forQuery: query)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .opacity(0.9)

                                Text(city.displayName)
                                    .font(.footnote)

                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if city.id != suggestions.last?.id {
                            Divider().overlay(Color.white.opacity(0.12))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 14)
        .padding(.horizontal, 16)
    }

    var weatherCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentCity)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(conditionText)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.85))

                    Text(tempText)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .padding(.top, 4)
                }

                Spacer()

                AnimatedWeatherIcon(condition: conditionText)
            }

            Divider().overlay(Color.white.opacity(0.10))

            HStack {
                Text(hiLoText)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Spacer()
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 22, x: 0, y: 16)
        .padding(.horizontal, 16)
    }

    var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Image(systemName: "clock")
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Time")
                        .font(.subheadline.weight(.semibold))

                    Text("Local device clock")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                Spacer()
            }

            Text("\(currentTime) \(currentDay)")
                .font(.title3.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.26), radius: 18, x: 0, y: 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - OLED helpers
extension ContentView {
    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "/")
    }

    private func updateTimeOnly() {
        let now = Date()
        currentTime = timeFormatter.string(from: now)
        currentDay = dayFormatter.string(from: now)
    }

    private func advanceOLEDSection() {
        switch currentOLEDSection {
        case .time:
            currentOLEDSection = .weather
        case .weather:
            currentOLEDSection = .time
        }
    }

    private func pushActiveOLEDSectionIfNeeded() {
        guard isActive, ble.isConnected else { return }

        switch currentOLEDSection {
        case .time:
            ble.send("MODE:TIME")
            sendTimeDataPacket()

        case .weather:
            ble.send("MODE:WEATHER")
            sendWeatherDataPacket()
        }
    }

    private func sendPlaceDataPacket() {
        guard ble.isConnected else { return }
        ble.send("PLACE:\(sanitize(currentCity))")
    }

    private func sendTimeDataPacket() {
        guard ble.isConnected else { return }
        ble.send("TIME:\(sanitize(currentTime))|\(sanitize(currentDay))")
    }

    private func sendWeatherDataPacket() {
        guard ble.isConnected else { return }

        let t = tempText.replacingOccurrences(of: "°", with: "")
        let hi = extractHi()
        let lo = extractLo()

        ble.send("WEATHER:\(sanitize(currentCity))|\(sanitize(t))|H\(sanitize(hi))|L\(sanitize(lo))|\(sanitize(conditionText))")
    }
}

// MARK: - Suggestions
extension ContentView {
    private func fetchSuggestions(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = "https://api.openweathermap.org/geo/1.0/direct?q=\(encoded)&limit=5&appid=\(apiKey)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }

            if let decoded = try? JSONDecoder().decode([GeoCity].self, from: data) {
                DispatchQueue.main.async {
                    self.suggestions = decoded
                }
            }
        }.resume()
    }
}

// MARK: - Weather fetch
extension ContentView {
    private func fetchWeather(forQuery query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=\(encoded)&units=imperial&appid=\(apiKey)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data else { return }

            if let error {
                print("Weather request error: \(error)")
                return
            }

            let decoded: WeatherResponse
            do {
                decoded = try JSONDecoder().decode(WeatherResponse.self, from: data)
            } catch {
                print("Weather decode failed: \(error)")
                return
            }

            DispatchQueue.main.async {
                currentCity = decoded.name
                let t = Int(round(decoded.main.temp))
                let hi = Int(round(decoded.main.tempMax))
                let lo = Int(round(decoded.main.tempMin))
                let cond = decoded.weather.first?.main ?? "--"

                tempText = "\(t)°"
                conditionText = cond
                hiLoText = "H \(hi)° L \(lo)°"

                // Only push the currently visible OLED section.
                if isActive {
                    pushActiveOLEDSectionIfNeeded()
                }
            }
        }.resume()
    }

    private func extractHi() -> String {
        let cleaned = hiLoText.replacingOccurrences(of: "°", with: "")
        guard let hRange = cleaned.range(of: "H "),
              let lRange = cleaned.range(of: " L ") else {
            return "--"
        }

        let hi = cleaned[hRange.upperBound..<lRange.lowerBound]
        return String(hi).trimmingCharacters(in: .whitespaces)
    }

    private func extractLo() -> String {
        let cleaned = hiLoText.replacingOccurrences(of: "°", with: "")
        guard let lRange = cleaned.range(of: " L ") else {
            return "--"
        }

        let lo = cleaned[lRange.upperBound...]
        return String(lo).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Background
extension ContentView {
    private func dynamicBackground(condition: String) -> LinearGradient {
        let c = condition.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour >= 21 || hour <= 4

        if c.contains("snow") {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(hue: 0.60, saturation: 0.20, brightness: isNight ? 0.22 : 0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if c.contains("rain") || c.contains("drizzle") || c.contains("storm") {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(hue: 0.60, saturation: 0.40, brightness: isNight ? 0.18 : 0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if c.contains("mist") || c.contains("fog") || c.contains("haze") {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(hue: 0.60, saturation: 0.10, brightness: isNight ? 0.18 : 0.26)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if c.contains("cloud") || c.contains("overcast") {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(hue: 0.62, saturation: 0.25, brightness: isNight ? 0.18 : 0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.black,
                Color(hue: 0.58, saturation: 0.50, brightness: isNight ? 0.20 : 0.30)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct AnimatedWeatherIcon: View {
    let condition: String
    @State private var animate = false

    private var kind: IconKind {
        let c = condition.lowercased()
        if c.contains("rain") || c.contains("drizzle") || c.contains("storm") { return .rain }
        if c.contains("snow") { return .snow }
        if c.contains("cloud") || c.contains("overcast") { return .clouds }
        return .sun
    }

    enum IconKind { case sun, clouds, rain, snow }

    var body: some View {
        ZStack {
            switch kind {
            case .sun:
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                    .rotationEffect(.degrees(animate ? 8 : -8))
                    .shadow(color: .yellow.opacity(0.5), radius: 10)

            case .clouds:
                ZStack {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 36))
                        .offset(x: animate ? 4 : -4, y: 0)

                    Image(systemName: "cloud.fill")
                        .font(.system(size: 28))
                        .offset(x: animate ? -6 : 6, y: 10)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)

            case .rain:
                ZStack {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)

                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.cyan.opacity(0.95))
                            .offset(x: CGFloat(-10 + i * 10), y: animate ? 12 : 0)
                            .opacity(animate ? 0.3 + 0.2 * Double(i) : 0.95)
                    }
                }

            case .snow:
                ZStack {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)

                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "snowflake")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .offset(x: CGFloat(-12 + i * 8), y: animate ? 10 : -2)
                            .opacity(animate ? 0.3 + 0.15 * Double(i) : 0.95)
                    }
                }
            }
        }
        .frame(width: 72, height: 72)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
