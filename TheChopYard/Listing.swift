import Foundation
import CoreLocation
import FirebaseFirestore

struct Listing: Identifiable, Decodable, Equatable, Hashable {
    @DocumentID var id: String?

    var title: String
    var price: Double
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var imageUrls: [String]
    var sellerId: String
    var timestamp: Date
    var description: String?
    var category: String?
    var viewCount: Int?
    var saveCount: Int?

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: Listing, rhs: Listing) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.price == rhs.price &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.locationName == rhs.locationName &&
               lhs.imageUrls == rhs.imageUrls &&
               lhs.sellerId == rhs.sellerId &&
               lhs.timestamp == rhs.timestamp &&
               lhs.description == rhs.description &&
               lhs.category == rhs.category &&
               lhs.viewCount == rhs.viewCount &&
               lhs.saveCount == rhs.saveCount
    }

    func formattedDistance(from userLocation: CLLocation) -> String {
        let distanceInMeters = clLocation.distance(from: userLocation)
        let miles = distanceInMeters / 1609.34

        if miles < 0.1 {
            return "Very close"
        } else {
            return String(format: "%.1f miles away", miles)
        }
    }
}
