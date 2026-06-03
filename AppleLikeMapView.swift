import SwiftUI
import MapKit
import CoreLocation
struct AppleLikeMapView: UIViewRepresentable {
    @Binding var route: MKRoute?
    @Binding var trackingMode: MKUserTrackingMode
    let showsMiniMapTilt: Bool
    let userLocation: CLLocation?
    let recenterToken: Int
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = trackingMode
        map.pointOfInterestFilter = .includingAll
        map.showsCompass = false
        map.showsScale = false
        // keep it “Apple-ish”
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        // tracking mode
        if map.userTrackingMode != trackingMode {
            map.setUserTrackingMode(trackingMode, animated: true)
        }
        // redraw route overlay
        context.coordinator.updateRouteOverlay(on: map, route: route)
        // force recenter when recenterToken changes OR when new route is set
        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken
            context.coordinator.recenter(map: map, route: route, userLocation: userLocation, tilt: showsMiniMapTilt)
        }
    }
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastRecenterToken: Int = -1
        private var routeOverlay: MKOverlay?
        func updateRouteOverlay(on map: MKMapView, route: MKRoute?) {
            if let existing = routeOverlay {
                map.removeOverlay(existing)
                routeOverlay = nil
            }
            guard let route else { return }
            routeOverlay = route.polyline
            map.addOverlay(route.polyline)
        }
        func recenter(map: MKMapView, route: MKRoute?, userLocation: CLLocation?, tilt: Bool) {
            // If we have a route, show the route nicely
            if let route {
                // Fit route with padding
                let rect = route.polyline.boundingMapRect
                let insets = UIEdgeInsets(top: 70, left: 50, bottom: 70, right: 50)
                map.setVisibleMapRect(rect, edgePadding: insets, animated: true)
                // Then apply heading-up camera centered on user if possible
                if let userLocation {
                    applyHeadingUpCamera(map: map, center: userLocation.coordinate, tilt: tilt, course: userLocation.course)
                }
                return
            }
            // No route: just follow user
            if let userLocation {
                applyHeadingUpCamera(map: map, center: userLocation.coordinate, tilt: tilt, course: userLocation.course)
            }
        }
        private func applyHeadingUpCamera(map: MKMapView, center: CLLocationCoordinate2D, tilt: Bool, course: CLLocationDirection) {
            let heading: CLLocationDirection
            if course >= 0 && course <= 360 {
                heading = course
            } else {
                heading = 0
            }
            let camera = MKMapCamera()
            camera.centerCoordinate = center
            camera.heading = heading                 //this is what makes “blue line straight up”
            camera.pitch = tilt ? 55 : 0            // 3D-ish tilt
            camera.altitude = 600                   // zoom level
            map.setCamera(camera, animated: true)
        }
        // MARK: MKMapViewDelegate
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = UIColor.systemBlue
                r.lineWidth = 6
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}



