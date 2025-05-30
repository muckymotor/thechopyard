import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionAndFetchLocation() {
        // Perform location services check off the main thread
        DispatchQueue.global().async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()

            DispatchQueue.main.async {
                if servicesEnabled {
                    if self.authorizationStatus == .notDetermined {
                        self.manager.requestWhenInUseAuthorization()
                    } else if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                        self.manager.requestLocation()
                    }
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else {
            location = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
