import SwiftUI
import MapKit
import Combine
import CoreLocation

struct MapsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var nav: NavigationManager

    let isActive: Bool

    @State private var destinationText: String = ""
    @State private var trackingMode: MKUserTrackingMode = .followWithHeading
    @State private var travelMode: TravelMode = .walking
    @State private var showTilt: Bool = true
    @State private var recenterToken: Int = 0
    @State private var showSteps: Bool = false
    @State private var oledMiniMap: Bool = false
    @State private var geoRoadsLoaded: Bool = false

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    topHeader
                    mapCard
                    directionsCard
                    stepsCard
                    Spacer(minLength: 18)
                }
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .foregroundColor(.white)
        .onAppear {
            location.requestPermission()
            location.start()

            if !geoRoadsLoaded {
                GeoJSONRoadSource.shared.loadFromBundle(named: "roads")
                geoRoadsLoaded = true
            }

            sendMapPacketIfActive()
        }
        .onReceive(location.$currentLocation.compactMap { $0 }) { loc in
            nav.updateUserLocation(loc, mode: travelMode)
            if oledMiniMap {
                sendMapPacketIfActive()
            }
        }
        .onChange(of: isActive) { _, _ in
            sendMapPacketIfActive()
        }
        .onChange(of: nav.currentRoute?.distance ?? 0) { _, _ in
            forceRecenter()
            sendMapPacketIfActive()
        }
        .onChange(of: nav.navLine1) { _, _ in
            sendMapPacketIfActive()
        }
        .onChange(of: nav.navLine2) { _, _ in
            sendMapPacketIfActive()
        }
        .onChange(of: nav.navLine3) { _, _ in
            sendMapPacketIfActive()
        }
        .onChange(of: ble.isConnected) { _, _ in
            sendMapPacketIfActive()
        }
    }
}

// MARK: - UI
private extension MapsView {
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.black, Color(hue: 0.58, saturation: 0.50, brightness: 0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var topHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("ARIS")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .kerning(5)

                Text("Maps + Directions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.70))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text(location.statusText)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.80))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }

    var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Map")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.70))

                Spacer()

                Text(nav.routeStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }

            ZStack(alignment: .topTrailing) {
                AppleLikeMapView(
                    route: $nav.currentRoute,
                    trackingMode: $trackingMode,
                    showsMiniMapTilt: showTilt,
                    userLocation: location.currentLocation,
                    recenterToken: recenterToken
                )
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        forceRecenter()
                    } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.callout.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }

                    Button {
                        showTilt.toggle()
                        forceRecenter()
                    } label: {
                        Image(systemName: showTilt ? "view.3d" : "view.2d")
                            .font(.callout.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }

                    Button {
                        oledMiniMap.toggle()
                        sendMapPacketIfActive()
                    } label: {
                        Image(systemName: oledMiniMap ? "map.fill" : "list.bullet.rectangle")
                            .font(.callout.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }
                }
                .padding(10)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 22, x: 0, y: 16)
        .padding(.horizontal, 16)
    }

    var directionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Directions")
                    .font(.headline.weight(.semibold))
                Spacer()
            }

            Picker("Mode", selection: $travelMode) {
                ForEach(TravelMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .opacity(0.9)

                    TextField("Enter destination", text: $destinationText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
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
                    startRoute()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text(nav.isRouting ? "..." : "Go")
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.cyan.opacity(0.35), radius: 14, x: 0, y: 10)
                }
                .disabled(nav.isRouting)
            }

            Divider().overlay(Color.white.opacity(0.10))

            HStack {
                statPill(title: "Distance", value: nav.distanceText)
                Spacer()
                statPill(title: "ETA", value: nav.etaText)
                Spacer()
                statPill(title: "Step", value: nav.stepIndexText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Next Step")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.70))

                Text(nav.nextInstruction.isEmpty ? "--" : nav.nextInstruction)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 22, x: 0, y: 16)
        .padding(.horizontal, 16)
    }

    var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    showSteps.toggle()
                }
            } label: {
                HStack {
                    Text("Steps")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("\(nav.routeSteps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    Image(systemName: showSteps ? "chevron.up" : "chevron.down")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSteps {
                if nav.routeSteps.isEmpty {
                    Text("No steps yet. Enter a destination and press Go.")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(nav.routeSteps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                                    .background(Color.white.opacity(0.10))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.instruction)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.white.opacity(0.95))
                                        .lineLimit(3)

                                    Text(step.distanceText)
                                        .font(.caption)
                                        .foregroundStyle(Color.white.opacity(0.70))
                                }

                                Spacer()
                            }

                            if idx != nav.routeSteps.count - 1 {
                                Divider().overlay(Color.white.opacity(0.10))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 22, x: 0, y: 16)
        .padding(.horizontal, 16)
    }

    func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.70))

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    func startRoute() {
        guard let userLoc = location.currentLocation else {
            nav.routeStatus = "Waiting for GPS..."
            return
        }

        nav.calculateRoute(from: userLoc, toQuery: destinationText, mode: travelMode)
        forceRecenter()
        sendMapPacketIfActive()
    }

    func forceRecenter() {
        trackingMode = .followWithHeading
        recenterToken += 1
    }
}

// MARK: - OLED / BLE helpers
private extension MapsView {
    func sendMapPacketIfActive() {
        guard isActive, ble.isConnected else { return }

        let turn = classifyTurn(nav.navLine2)
        let nextDist = nav.navLine1.replacingOccurrences(of: "IN ", with: "")
        let road = extractRoad(nav.navLine2)
        let remain = extractRemain(nav.navLine3)
        let eta = extractEta(nav.navLine3)

        ble.send("MAP:\(sanitize(turn))|\(sanitize(nextDist))|\(sanitize(road))|\(sanitize(remain))|\(sanitize(eta))")
        ble.send(oledMiniMap ? "MAPVIEW:MINI" : "MAPVIEW:TEXT")
        ble.send("MODE:MAP")

        if oledMiniMap {
            sendOLEDMiniMapIfNeeded()
        }
    }

    func sendOLEDMiniMapIfNeeded() {
        guard isActive, ble.isConnected, oledMiniMap else { return }
        guard let userLoc = location.currentLocation else { return }
        guard let route = nav.currentRoute else { return }

        let heading = normalizedHeading(from: location.headingDegrees ?? userLoc.course)

        let roadPolylines = GeoJSONRoadSource.shared.nearbyRoads(
            around: userLoc.coordinate,
            radiusMeters: 350,
            maxRoads: 12
        )

        let roadPoints = makeMiniMapRoadPoints(
            roads: roadPolylines,
            userLocation: userLoc
        )

        let routePoints = makeMiniMapPoints(
            route: route,
            userLocation: userLoc
        )

        ble.send("PLY:24,44,\(heading)")
        sendRoadPointChunks(roadPoints)
        sendRoutePointChunks(routePoints)
    }

    func normalizedHeading(from heading: CLLocationDirection) -> Int {
        if heading >= 0 && heading <= 360 {
            return Int(heading)
        }
        return 0
    }

    func makeMiniMapPoints(route: MKRoute, userLocation: CLLocation) -> [CGPoint] {
        let count = route.polyline.pointCount
        guard count > 1 else { return [] }

        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: count
        )
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))

        let simplified = simplifyCoordinates(coords, targetCount: 16)

        let headingDeg = normalizedHeading(from: location.headingDegrees ?? userLocation.course)
        let headingRad = -CGFloat(headingDeg) * .pi / 180.0

        let anchorX: CGFloat = 24
        let anchorY: CGFloat = 44

        let metersPerHalfWidth: CGFloat = 220
        let metersPerHalfHeight: CGFloat = 260

        var out: [CGPoint] = []

        for c in simplified {
            let dxMeters = CGFloat(eastWestMeters(from: userLocation.coordinate, to: c))
            let dyMeters = CGFloat(northSouthMeters(from: userLocation.coordinate, to: c))

            let rx = dxMeters * cos(headingRad) - dyMeters * sin(headingRad)
            let ry = dxMeters * sin(headingRad) + dyMeters * cos(headingRad)

            var sx = anchorX + (rx / metersPerHalfWidth) * 20.0
            var sy = anchorY - (ry / metersPerHalfHeight) * 20.0

            sx = min(max(sx, 2), 45)
            sy = min(max(sy, 10), 53)

            out.append(CGPoint(x: sx, y: sy))
        }

        return out
    }

    func makeMiniMapRoadPoints(
        roads: [RoadPolyline],
        userLocation: CLLocation
    ) -> [[CGPoint]] {
        let headingDeg = normalizedHeading(from: location.headingDegrees ?? userLocation.course)
        let headingRad = -CGFloat(headingDeg) * .pi / 180.0

        let anchorX: CGFloat = 24
        let anchorY: CGFloat = 44

        let metersPerHalfWidth: CGFloat = 220
        let metersPerHalfHeight: CGFloat = 260

        var result: [[CGPoint]] = []

        for road in roads {
            var pts: [CGPoint] = []

            for c in road.coordinates {
                let dx = CGFloat(eastWestMeters(from: userLocation.coordinate, to: c))
                let dy = CGFloat(northSouthMeters(from: userLocation.coordinate, to: c))

                let rx = dx * cos(headingRad) - dy * sin(headingRad)
                let ry = dx * sin(headingRad) + dy * cos(headingRad)

                var sx = anchorX + (rx / metersPerHalfWidth) * 20.0
                var sy = anchorY - (ry / metersPerHalfHeight) * 20.0

                sx = min(max(sx, 2), 45)
                sy = min(max(sy, 10), 53)

                pts.append(CGPoint(x: sx, y: sy))
            }

            if pts.count >= 2 {
                result.append(simplifyPointList(pts, targetCount: 10))
            }
        }

        return result
    }

    func simplifyCoordinates(_ coords: [CLLocationCoordinate2D], targetCount: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > targetCount, targetCount > 2 else { return coords }

        let step = Double(coords.count - 1) / Double(targetCount - 1)
        var out: [CLLocationCoordinate2D] = []

        for i in 0..<targetCount {
            let idx = min(Int(round(Double(i) * step)), coords.count - 1)
            out.append(coords[idx])
        }

        return out
    }

    func simplifyPointList(_ pts: [CGPoint], targetCount: Int) -> [CGPoint] {
        guard pts.count > targetCount, targetCount > 2 else { return pts }

        let step = Double(pts.count - 1) / Double(targetCount - 1)
        var out: [CGPoint] = []

        for i in 0..<targetCount {
            let idx = min(Int(round(Double(i) * step)), pts.count - 1)
            out.append(pts[idx])
        }

        return out
    }

    func eastWestMeters(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
        let lat = origin.latitude * .pi / 180.0
        let metersPerDegLon = 111320.0 * cos(lat)
        return (target.longitude - origin.longitude) * metersPerDegLon
    }

    func northSouthMeters(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> Double {
        let metersPerDegLat = 111132.0
        return (target.latitude - origin.latitude) * metersPerDegLat
    }

    func sendRoadPointChunks(_ roads: [[CGPoint]]) {
        guard !roads.isEmpty else { return }

        var flat: [CGPoint] = []

        for road in roads {
            flat.append(contentsOf: road)
            flat.append(CGPoint(x: -1, y: -1))
        }

        let chunkSize = 6
        let totalChunks = Int(ceil(Double(flat.count) / Double(chunkSize)))

        for chunkIndex in 0..<totalChunks {
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, flat.count)
            let slice = flat[start..<end]

            let payload = slice.map { pt in
                "\(Int(pt.x)),\(Int(pt.y))"
            }.joined(separator: ",")

            ble.send("RD:\(chunkIndex),\(totalChunks),\(payload)")
        }
    }

    func sendRoutePointChunks(_ points: [CGPoint]) {
        guard !points.isEmpty else { return }

        let clipped = points.map {
            CGPoint(
                x: min(max(Int(round($0.x)), 2), 45),
                y: min(max(Int(round($0.y)), 10), 53)
            )
        }

        let chunkSize = 6
        let totalChunks = Int(ceil(Double(clipped.count) / Double(chunkSize)))

        for chunkIndex in 0..<totalChunks {
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, clipped.count)
            let slice = clipped[start..<end]
            let payload = slice.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: ",")
            ble.send("RTE:\(chunkIndex),\(totalChunks),\(payload)")
        }
    }

    func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "/")
    }

    func classifyTurn(_ text: String) -> String {
        let t = text.uppercased()
        if t.contains("U-TURN") { return "U-TURN" }
        if t.contains("LEFT") { return "LEFT" }
        if t.contains("RIGHT") { return "RIGHT" }
        if t.contains("ARRIVED") || t.contains("DONE") { return "ARRIVED" }
        return "STRAIGHT"
    }

    func extractRoad(_ text: String) -> String {
        let t = text.uppercased()
        let prefixes = ["LEFT ", "RIGHT ", "STRAIGHT ", "U-TURN ", "SLIGHT L ", "SLIGHT R ", "MERGE ", "EXIT "]
        for prefix in prefixes {
            if t.hasPrefix(prefix) {
                return String(t.dropFirst(prefix.count))
            }
        }
        return t
    }

    func extractRemain(_ text: String) -> String {
        let t = text.uppercased()
        guard let remRange = t.range(of: "REM "),
              let etaRange = t.range(of: " ETA ") else {
            return "--"
        }
        return String(t[remRange.upperBound..<etaRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    func extractEta(_ text: String) -> String {
        let t = text.uppercased()
        guard let etaRange = t.range(of: " ETA ") else {
            return "--"
        }
        return "ETA " + String(t[etaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
