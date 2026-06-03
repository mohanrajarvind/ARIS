import Foundation
import CoreLocation

struct RoadPolyline {
    let coordinates: [CLLocationCoordinate2D]
}

final class GeoJSONRoadSource {
    static let shared = GeoJSONRoadSource()

    private(set) var roads: [RoadPolyline] = []
    private var loaded = false

    private init() {}

    func loadFromBundle(named fileName: String = "roads") {
        guard !loaded else { return }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "geojson") else {
            print("GeoJSONRoadSource: missing \(fileName).geojson in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            roads = try parseGeoJSON(data: data)
            loaded = true
            print("GeoJSONRoadSource: loaded \(roads.count) road polylines")
        } catch {
            print("GeoJSONRoadSource load error: \(error)")
        }
    }

    func nearbyRoads(
        around center: CLLocationCoordinate2D,
        radiusMeters: Double = 350,
        maxRoads: Int = 12
    ) -> [RoadPolyline] {
        guard !roads.isEmpty else { return [] }

        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let scored: [(RoadPolyline, Double)] = roads.compactMap { road in
            guard !road.coordinates.isEmpty else { return nil }

            var minDistance = Double.greatestFiniteMagnitude

            for coord in road.coordinates {
                let d = centerLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                if d < minDistance {
                    minDistance = d
                }
            }

            guard minDistance <= radiusMeters else { return nil }
            return (road, minDistance)
        }

        return scored
            .sorted { $0.1 < $1.1 }
            .prefix(maxRoads)
            .map { $0.0 }
    }

    private func parseGeoJSON(data: Data) throws -> [RoadPolyline] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])

        guard let root = obj as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            return []
        }

        var output: [RoadPolyline] = []

        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else {
                continue
            }

            if type == "LineString" {
                if let coords = geometry["coordinates"] as? [[Double]] {
                    let line = coords.compactMap { pair -> CLLocationCoordinate2D? in
                        guard pair.count >= 2 else { return nil }
                        return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                    }
                    if line.count >= 2 {
                        output.append(RoadPolyline(coordinates: line))
                    }
                }
            } else if type == "MultiLineString" {
                if let groups = geometry["coordinates"] as? [[[Double]]] {
                    for coords in groups {
                        let line = coords.compactMap { pair -> CLLocationCoordinate2D? in
                            guard pair.count >= 2 else { return nil }
                            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                        }
                        if line.count >= 2 {
                            output.append(RoadPolyline(coordinates: line))
                        }
                    }
                }
            }
        }

        return output
    }
}
