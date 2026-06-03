import Foundation
import MapKit
import CoreLocation
import Combine

enum TravelMode: String, CaseIterable, Identifiable {
    case walking = "Walking"
    case driving = "Driving"
    var id: String { rawValue }

    var mkType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .driving: return .automobile
        }
    }
}

// ✅ Used by MapsView "Steps" drawer
struct NavStepUI: Identifiable {
    let id = UUID()
    let instruction: String
    let distanceMeters: Double

    var distanceText: String {
        NavigationManager.formatImperialDistance(distanceMeters)
    }
}

final class NavigationManager: ObservableObject {

    // ✅ Used by MapsView to draw the route polyline
    @Published var currentRoute: MKRoute?

    // ✅ Used by MapsView to list all steps (open/close drawer)
    @Published var routeSteps: [NavStepUI] = []

    // UI fields (Directions card)
    @Published var isRouting: Bool = false
    @Published var routeStatus: String = "Enter a destination"
    @Published var distanceText: String = "--"     // remaining total distance
    @Published var etaText: String = "--"          // remaining ETA
    @Published var nextInstruction: String = "--"
    @Published var stepIndexText: String = "--"

    // OLED/BLE fields
    @Published var navLine1: String = "IN --"      // "IN 250FT"
    @Published var navLine2: String = "--"         // "LEFT LEVY RD"
    @Published var navLine3: String = "--"         // "REM 1.8MI ETA 6M"

    private var steps: [MKRoute.Step] = []
    private var stepIndex: Int = 0

    // Overall route totals (initial)
    private var totalDistanceMeters: CLLocationDistance = 0
    private var totalEtaSeconds: TimeInterval = 0

    // Used to estimate remaining ETA by remainingDistance / avgSpeed
    private var avgSpeedMps: Double = 0.0

    // ✅ Reroute state
    private var destinationItem: MKMapItem?
    private var destinationQuerySaved: String = ""
    private var lastRerouteAt: Date = .distantPast
    private var offRouteHits: Int = 0

    // Tune these
    private let rerouteCooldown: TimeInterval = 8.0          // seconds between reroutes
    private let offRouteHitsNeeded: Int = 3                  // require N consecutive off-route checks
    private let offRouteThresholdWalking: CLLocationDistance = 30  // meters
    private let offRouteThresholdDriving: CLLocationDistance = 70  // meters

    // MARK: - Route (user typed query)

    func calculateRoute(from userLocation: CLLocation,
                        toQuery destinationQuery: String,
                        mode: TravelMode) {

        let trimmed = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            routeStatus = "Enter a destination"
            return
        }

        isRouting = true
        routeStatus = "Searching destination..."

        // Reset UI + route
        currentRoute = nil
        routeSteps = []
        destinationItem = nil
        destinationQuerySaved = trimmed
        offRouteHits = 0

        distanceText = "--"
        etaText = "--"
        nextInstruction = "--"
        stepIndexText = "--"

        navLine1 = "IN --"
        navLine2 = "--"
        navLine3 = "--"

        steps = []
        stepIndex = 0
        totalDistanceMeters = 0
        totalEtaSeconds = 0
        avgSpeedMps = 0

        // 1) Convert typed text -> MKMapItem using MKLocalSearch
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: userLocation.coordinate,
                                            latitudinalMeters: 30_000,
                                            longitudinalMeters: 30_000)

        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isRouting = false
                    self.routeStatus = "Search error"
                    self.nextInstruction = "Search error: \(error.localizedDescription)"
                    self.navLine1 = "IN --"
                    self.navLine2 = "ERROR"
                    self.navLine3 = "--"
                }
                return
            }

            guard let item = response?.mapItems.first else {
                DispatchQueue.main.async {
                    self.isRouting = false
                    self.routeStatus = "No destination found"
                    self.nextInstruction = "No destination found"
                    self.navLine1 = "IN --"
                    self.navLine2 = "NO DEST"
                    self.navLine3 = "--"
                }
                return
            }

            DispatchQueue.main.async {
                self.destinationItem = item // ✅ save for reroutes
                self.routeStatus = "Calculating route..."
            }

            // 2) Route request
            self.calculateRoute(from: userLocation, toItem: item, mode: mode)
        }
    }

    // MARK: - Route (saved destination item — used for reroute too)

    private func calculateRoute(from userLocation: CLLocation,
                                toItem item: MKMapItem,
                                mode: TravelMode) {

        let dirReq = MKDirections.Request()
        dirReq.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        dirReq.destination = item
        dirReq.transportType = mode.mkType

        MKDirections(request: dirReq).calculate { [weak self] dirResp, dirErr in
            guard let self = self else { return }

            if let dirErr = dirErr {
                DispatchQueue.main.async {
                    self.isRouting = false
                    self.routeStatus = "Route error"
                    self.nextInstruction = "Route error: \(dirErr.localizedDescription)"
                    self.navLine1 = "IN --"
                    self.navLine2 = "ERROR"
                    self.navLine3 = "--"
                }
                return
            }

            guard let route = dirResp?.routes.first else {
                DispatchQueue.main.async {
                    self.isRouting = false
                    self.routeStatus = "No route found"
                    self.nextInstruction = "No route found"
                    self.navLine1 = "IN --"
                    self.navLine2 = "NO ROUTE"
                    self.navLine3 = "--"
                }
                return
            }

            let filteredSteps = route.steps.filter { !$0.instructions.isEmpty }

            DispatchQueue.main.async {
                // ✅ Save route so MapsView can draw it
                self.currentRoute = route

                // ✅ Save steps for UI + Steps drawer
                self.steps = filteredSteps
                self.routeSteps = filteredSteps.map { step in
                    NavStepUI(instruction: step.instructions, distanceMeters: step.distance)
                }

                self.stepIndex = 0

                self.totalDistanceMeters = route.distance
                self.totalEtaSeconds = route.expectedTravelTime

                // Average speed estimate for ETA updates
                if route.expectedTravelTime > 1 {
                    self.avgSpeedMps = route.distance / route.expectedTravelTime
                } else {
                    self.avgSpeedMps = 0
                }

                self.offRouteHits = 0

                if self.steps.isEmpty {
                    self.routeStatus = "Route ready"
                    self.nextInstruction = "No step instructions"
                    self.stepIndexText = "--"
                    self.distanceText = Self.formatImperialDistance(route.distance)
                    self.etaText = Self.formatETA(route.expectedTravelTime)

                    self.navLine1 = "IN --"
                    self.navLine2 = "NO STEPS"
                    self.navLine3 = "REM \(Self.formatImperialDistanceShort(route.distance)) ETA \(Self.formatETAShort(route.expectedTravelTime))"

                    self.isRouting = false
                    return
                }

                self.routeStatus = "Route ready"
                self.nextInstruction = self.steps[0].instructions
                self.stepIndexText = "Step 1 of \(self.steps.count)"

                // Initialize remaining values using current location
                self.recomputeRemaining(userLoc: userLocation, mode: mode)

                self.isRouting = false
            }
        }
    }

    // MARK: - Auto-update & Auto-advance + ✅ Auto-reroute

    func updateUserLocation(_ userLoc: CLLocation, mode: TravelMode) {
        // If no steps/route, nothing to do
        guard let route = currentRoute else { return }
        guard !isRouting else { return }
        guard routeStatus != "Arrived" else { return }

        // ✅ Off-route detection
        let threshold = (mode == .walking) ? offRouteThresholdWalking : offRouteThresholdDriving
        let distanceToRoute = Self.distance(from: userLoc.coordinate, to: route.polyline)

        if distanceToRoute > threshold {
            offRouteHits += 1
        } else {
            offRouteHits = 0
        }

        // ✅ Reroute if off-route for a few updates + cooldown passed
        if offRouteHits >= offRouteHitsNeeded,
           Date().timeIntervalSince(lastRerouteAt) >= rerouteCooldown {
            lastRerouteAt = Date()
            offRouteHits = 0
            reroute(from: userLoc, mode: mode)
            return
        }

        // ---- Your existing step logic (advance + recompute) ----
        guard !steps.isEmpty else { return }
        guard stepIndex >= 0, stepIndex < steps.count else { return }

        let step = steps[stepIndex]
        let endCoord = step.polyline.coordinateAtEnd()
        let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)

        let distToEnd = userLoc.distance(from: endLoc)

        let thresholdToAdvance: CLLocationDistance = (mode == .walking) ? 18 : 45
        if distToEnd <= thresholdToAdvance {
            advanceToNextStep()
        }

        recomputeRemaining(userLoc: userLoc, mode: mode)
    }

    private func reroute(from userLoc: CLLocation, mode: TravelMode) {
        guard let dest = destinationItem else {
            // fallback: if we don't have a map item yet, nothing to reroute to
            return
        }

        isRouting = true
        routeStatus = "Rerouting..."

        // Keep showing something useful while rerouting
        navLine2 = "REROUTE"

        calculateRoute(from: userLoc, toItem: dest, mode: mode)
    }

    func advanceToNextStep() {
        guard !steps.isEmpty else { return }

        if stepIndex < steps.count - 1 {
            stepIndex += 1
            nextInstruction = steps[stepIndex].instructions
            stepIndexText = "Step \(stepIndex + 1) of \(steps.count)"
            routeStatus = "Routing"
        } else {
            routeStatus = "Arrived"
            nextInstruction = "Arrived"
            stepIndexText = "Step \(steps.count) of \(steps.count)"

            navLine1 = "ARRIVED"
            navLine2 = "DONE"
            navLine3 = "REM 0MI ETA 0M"
        }
    }

    // MARK: - Remaining Distance/ETA calculation

    private func recomputeRemaining(userLoc: CLLocation, mode: TravelMode) {
        guard !steps.isEmpty else { return }
        guard stepIndex >= 0, stepIndex < steps.count else { return }

        let endCoord = steps[stepIndex].polyline.coordinateAtEnd()
        let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
        let distToNext = userLoc.distance(from: endLoc)

        var remaining = distToNext
        if stepIndex + 1 < steps.count {
            for i in (stepIndex + 1)..<steps.count {
                remaining += steps[i].distance
            }
        }

        let remainingEta: TimeInterval
        if avgSpeedMps > 0.1 {
            remainingEta = remaining / avgSpeedMps
        } else if totalDistanceMeters > 1, totalEtaSeconds > 1 {
            remainingEta = totalEtaSeconds * (remaining / totalDistanceMeters)
        } else {
            remainingEta = 0
        }

        distanceText = Self.formatImperialDistance(remaining)
        etaText = Self.formatETA(remainingEta)

        navLine1 = "IN " + Self.formatNextStepDistanceImperial(distToNext)
        navLine2 = buildTurnRoadLine(from: nextInstruction)
        navLine3 = "REM \(Self.formatImperialDistanceShort(remaining)) ETA \(Self.formatETAShort(remainingEta))"
    }

    // MARK: - Build "LEFT LEVY RD" style line

    private func buildTurnRoadLine(from instruction: String) -> String {
        let upper = instruction.uppercased()

        let turnWord: String
        if upper.contains("U-TURN") { turnWord = "U-TURN" }
        else if upper.contains("SLIGHT LEFT") { turnWord = "SLIGHT L" }
        else if upper.contains("SLIGHT RIGHT") { turnWord = "SLIGHT R" }
        else if upper.contains("TURN LEFT") { turnWord = "LEFT" }
        else if upper.contains("TURN RIGHT") { turnWord = "RIGHT" }
        else if upper.contains("MERGE") { turnWord = "MERGE" }
        else if upper.contains("EXIT") { turnWord = "EXIT" }
        else { turnWord = "STRAIGHT" }

        let road = abbreviateRoad(extractRoadName(from: instruction))
        if road.isEmpty { return turnWord }
        return "\(turnWord) \(road)"
    }

    private func extractRoadName(from instr: String) -> String {
        let s = instr
        let keys = [" onto ", " on ", " toward "]
        for key in keys {
            if let r = s.range(of: key, options: .caseInsensitive) {
                let after = s[r.upperBound...]
                return after.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func abbreviateRoad(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var s = text.uppercased()

        let replacements: [(String, String)] = [
            ("BOULEVARD", "BLVD"),
            ("AVENUE", "AVE"),
            ("STREET", "ST"),
            ("ROAD", "RD"),
            ("DRIVE", "DR"),
            ("HIGHWAY", "HWY"),
            ("FREEWAY", "FWY"),
            ("PARKWAY", "PKWY"),
            ("LANE", "LN"),
            ("COURT", "CT"),
            ("CIRCLE", "CIR"),
            ("PLACE", "PL"),
            ("TERRACE", "TER"),
            ("WAY", "WAY")
        ]

        for (from, to) in replacements {
            s = s.replacingOccurrences(of: " \(from) ", with: " \(to) ")
            if s.hasSuffix(" \(from)") { s = s.replacingOccurrences(of: " \(from)", with: " \(to)") }
        }

        s = s.replacingOccurrences(of: ",", with: "")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Distance to route polyline (off-route detection)

    /// Returns minimum distance (meters) from a coordinate to a polyline.
    static func distance(from coordinate: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        let p = MKMapPoint(coordinate)
        let points = polyline.points()
        let count = polyline.pointCount
        guard count >= 2 else { return .greatestFiniteMagnitude }

        var minDist = CLLocationDistance.greatestFiniteMagnitude

        for i in 0..<(count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let d = distanceToSegment(p, a, b)
            if d < minDist { minDist = d }
        }

        return minDist
    }

    /// Distance from point p to segment ab in MKMapPoint space (meters)
    static func distanceToSegment(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> CLLocationDistance {
        let ax = a.x, ay = a.y
        let bx = b.x, by = b.y
        let px = p.x, py = p.y

        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay

        let abLen2 = abx * abx + aby * aby
        if abLen2 == 0 {
            return p.distance(to: a)   // updated
        }

        var t = (apx * abx + apy * aby) / abLen2
        t = max(0, min(1, t))

        let proj = MKMapPoint(x: ax + t * abx, y: ay + t * aby)
        return p.distance(to: proj)    // updated
    }

    // MARK: - Formatting (Imperial)

    static func formatImperialDistance(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        let miles = meters / 1609.344

        if miles >= 0.10 {
            return String(format: "%.1f mi", miles)
        } else {
            return "\(Int(round(feet))) ft"
        }
    }

    static func formatImperialDistanceShort(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        let miles = meters / 1609.344

        if miles >= 0.10 {
            return String(format: "%.1fMI", miles)
        } else {
            return "\(Int(round(feet)))FT"
        }
    }

    static func formatNextStepDistanceImperial(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        let miles = meters / 1609.344

        if miles < 0.20 {
            return "\(Int(round(feet)))FT"
        } else {
            return String(format: "%.1fMI", miles)
        }
    }

    static func formatETA(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(round(seconds / 60)))
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }

    static func formatETAShort(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(round(seconds / 60)))
        if totalMinutes < 60 { return "\(totalMinutes)M" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)H\(m)M"
    }
}

// Helper: last coordinate in a step polyline (end of that step)
private extension MKPolyline {
    func coordinateAtEnd() -> CLLocationCoordinate2D {
        let count = pointCount
        guard count > 0 else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }

        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: count
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords[count - 1]
    }
}
