import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var statusText: String = "Location: Not started"
    @Published var headingDegrees: CLLocationDirection?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.headingFilter = 5
        manager.activityType = .fitness
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        statusText = "Location: Updating..."
        manager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        statusText = "Location: Stopped"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "Location: Authorized"
        case .denied:
            statusText = "Location: Denied"
        case .restricted:
            statusText = "Location: Restricted"
        case .notDetermined:
            statusText = "Location: Not determined"
        @unknown default:
            statusText = "Location: Unknown"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        currentLocation = newest
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if h >= 0 && h <= 360 {
            headingDegrees = h
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Location error: \(error.localizedDescription)"
    }
}
