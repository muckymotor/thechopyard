//
//  HomeView.swift
//  TheChopYard
//
//  Created by Joseph Griffiths on 5/3/25.
//
import SwiftUI
import CoreLocation
import Firebase

struct Listing: Identifiable {
    var id: String
    var title: String
    var price: Double
    var location: CLLocation
    var imageUrls: [String]
    var sellerId: String
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    
    @Published var location: CLLocation? = nil

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Error: \(error)")
    }
}

struct HomeView: View {
    @StateObject private var locationManager = LocationManager() // Location manager for user location
    @State private var listings: [Listing] = [] // Listings fetched from Firebase

    var body: some View {
        VStack {
            if let userLocation = locationManager.location {
                Text("Your location: \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")
                    .padding()
                
                List(listings) { listing in
                    VStack(alignment: .leading) {
                        Text(listing.title)
                            .font(.headline)
                        Text("$\(listing.price, specifier: "%.2f")")
                        // Display listing's location and image URLs here
                    }
                    .padding()
                }
            } else {
                Text("Getting your location...")
                    .padding()
            }
        }
        .onAppear {
            fetchListings() // Fetch listings when the view appears
        }
    }

    // Fetch listings from Firebase or a static source for now
    private func fetchListings() {
        // Placeholder Firebase logic (replace with actual data fetching logic)
        listings = [
            Listing(id: "1", title: "Chopper Part 1", price: 99.99, location: CLLocation(latitude: 37.7749, longitude: -122.4194), imageUrls: [], sellerId: "user1"),
            Listing(id: "2", title: "Chopper Part 2", price: 199.99, location: CLLocation(latitude: 37.7749, longitude: -122.4194), imageUrls: [], sellerId: "user2")
        ]
    }
}
