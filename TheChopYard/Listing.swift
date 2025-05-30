import Foundation
import CoreLocation
import FirebaseFirestore

struct Listing: Identifiable, Equatable {
    var id: String
    var title: String
    var price: Double
    var location: CLLocation
    var locationName: String?
    var imageUrls: [String]
    var imageAspectRatios: [CGFloat]?   // ✅ Required for dynamic height
    var sellerId: String
    var timestamp: Date
    var description: String?
    var category: String?

    static func ==(lhs: Listing, rhs: Listing) -> Bool {
        lhs.id == rhs.id
    }

    func formattedDistance(from userLocation: CLLocation) -> String {
        let miles = location.distance(from: userLocation) / 1609.34
        return miles < 1.0 ? "Under 1 mile away" : String(format: "%.1f miles away", miles)
    }
}

extension Listing {
    init?(id: String, data: [String: Any]) {
        guard
            let title = data["title"] as? String,
            let price = data["price"] as? Double,
            let latitude = data["latitude"] as? CLLocationDegrees,
            let longitude = data["longitude"] as? CLLocationDegrees,
            let imageUrls = data["imageUrls"] as? [String],
            let sellerId = data["sellerId"] as? String,
            let timestamp = data["timestamp"] as? Timestamp
        else {
            return nil
        }

        self.id = id
        self.title = title
        self.price = price
        self.location = CLLocation(latitude: latitude, longitude: longitude)
        self.locationName = data["locationName"] as? String
        self.imageUrls = imageUrls
        self.imageAspectRatios = data["imageAspectRatios"] as? [CGFloat]
        self.sellerId = sellerId
        self.timestamp = timestamp.dateValue()
        self.description = data["description"] as? String
        self.category = data["category"] as? String
    }
}
