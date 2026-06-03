import Foundation

// MARK: - Weather Models (NON-MainActor)

struct WeatherResponse: Codable {
    struct Main: Codable {
        let temp: Double
        let tempMin: Double
        let tempMax: Double

        enum CodingKeys: String, CodingKey {
            case temp
            case tempMin = "temp_min"
            case tempMax = "temp_max"
        }
    }

    struct WeatherItem: Codable {
        let main: String?
        let description: String?
    }

    let name: String
    let main: Main
    let weather: [WeatherItem]
}

// MARK: - Geocoding Models (NON-MainActor)

struct GeoCity: Codable, Identifiable {
    let id = UUID()
    let name: String
    let state: String?
    let country: String

    private enum CodingKeys: String, CodingKey { case name, state, country }

    var displayName: String {
        var parts: [String] = [name]
        if let s = state, !s.isEmpty { parts.append(s) }
        parts.append(country)
        return parts.joined(separator: ", ")
    }

    var queryString: String {
        var parts: [String] = [name]
        if let s = state, !s.isEmpty { parts.append(s) }
        parts.append(country)
        return parts.joined(separator: ",")
    }
}
