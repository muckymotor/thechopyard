import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import Contacts

@available(iOS 16.0, *)
struct EditListingView: View {
    var onSave: ((Listing) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    private var originalListing: Listing

    @State private var title: String
    @State private var price: String
    @State private var listingDescription: String
    @State private var locationText: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedCategory: String

    @State private var newSelectedPhotoItems: [PhotosPickerItem] = []
    @State private var newUiImages: [UIImage] = []
    @State private var existingImageUrls: [String]

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = "Error"
    @State private var isShowingLocationSearch = false

    private let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private let db = Firestore.firestore()
    private let storage = Storage.storage().reference()

    init(listing: Listing, onSave: ((Listing) -> Void)? = nil) {
        self.originalListing = listing
        self.onSave = onSave
        _title = State(initialValue: listing.title)
        _price = State(initialValue: String(format: "%.2f", listing.price))
        _listingDescription = State(initialValue: listing.description ?? "")
        _locationText = State(initialValue: listing.locationName ?? "")
        _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: listing.latitude, longitude: listing.longitude))
        _selectedCategory = State(initialValue: listing.category ?? "")
        _existingImageUrls = State(initialValue: listing.imageUrls)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                photoSection
                submitSection
            }
            .navigationTitle("Edit Listing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingLocationSearch) {
            LocationSearchView { selectedPlace, coordinate in
                Task {
                    locationText = await extractCityAndState(from: selectedPlace)
                    selectedCoordinate = coordinate
                }
            }
        }
        .onChange(of: newSelectedPhotoItems) { _ in
            Task {
                var loadedImages: [UIImage] = []
                for item in newSelectedPhotoItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let compressed = image.compressedJPEG() {
                        loadedImages.append(UIImage(data: compressed) ?? image)
                    }
                }
                newUiImages = loadedImages
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var detailsSection: some View {
        Section(header: Text("Details")) {
            TextField("Title", text: $title)
            TextField("Price", text: $price).keyboardType(.decimalPad)
            TextField("Description", text: $listingDescription, axis: .vertical)
                .lineLimit(3...6)
            locationField
            categoryPicker
        }
    }

    private var locationField: some View {
        HStack {
            Text(locationText.isEmpty ? "Select Location" : locationText)
                .foregroundColor(locationText.isEmpty ? Color(UIColor.placeholderText) : .primary)
            Spacer()
            Button {
                isShowingLocationSearch = true
            } label: {
                Image(systemName: "map.fill")
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading) {
            Picker("Category", selection: $selectedCategory) {
                Text("Select Category").tag("")
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)

            if selectedCategory.isEmpty && !isSaving {
                Text("Please select a category.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 2)
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Photos")) {
            PhotosPicker(selection: $newSelectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                Text("Select New Photos (replaces all)")
            }

            if !newUiImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(newUiImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }
                }
            } else if !existingImageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(existingImageUrls, id: \.self) { urlString in
                            AsyncImage(url: URL(string: urlString)) { image in
                                image.resizable()
                            } placeholder: {
                                ProgressView()
                            }
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    private var submitSection: some View {
        Section {
            Button("Save Changes") {
                validateAndSaveChanges()
            }
            .disabled(isSaving || selectedCategory.isEmpty)

            if selectedCategory.isEmpty {
                Text("Please select a category to save.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func validateAndSaveChanges() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            triggerAlert(title: "Validation Error", message: "Title cannot be empty.")
            return
        }
        guard let priceValue = Double(price), priceValue > 0 else {
            triggerAlert(title: "Validation Error", message: "Invalid price. Must be a number greater than 0.")
            return
        }
        guard selectedCoordinate != nil else {
            triggerAlert(title: "Validation Error", message: "Location information is missing.")
            return
        }
        if selectedCategory.isEmpty {
            triggerAlert(title: "Validation Error", message: "Please select a category.")
            return
        }

        Task {
            await saveChanges()
        }
    }

    private func saveChanges() async {
        isSaving = true

        var finalImageUrlsToSave: [String] = originalListing.imageUrls

        if !newUiImages.isEmpty {
            for url in existingImageUrls {
                if let storagePath = try? Storage.storage().reference(forURL: url).fullPath {
                    try? await Storage.storage().reference(withPath: storagePath).delete()
                }
            }

            do {
                finalImageUrlsToSave = try await uploadImages(images: newUiImages)
            } catch {
                triggerAlert(title: "Upload Error", message: "Error uploading new images: \(error.localizedDescription)")
                isSaving = false
                return
            }
        }

        let currentLatitude = selectedCoordinate?.latitude ?? originalListing.latitude
        let currentLongitude = selectedCoordinate?.longitude ?? originalListing.longitude

        let updatedData: [String: Any] = [
            "title": title,
            "price": Double(price) ?? originalListing.price,
            "description": listingDescription.isEmpty ? NSNull() : listingDescription,
            "locationName": locationText.isEmpty ? NSNull() : locationText,
            "latitude": currentLatitude,
            "longitude": currentLongitude,
            "sellerId": originalListing.sellerId,
            "category": selectedCategory,
            "timestamp": Timestamp(date: Date()),
            "imageUrls": finalImageUrlsToSave
        ]

        await updateFirestore(with: updatedData)
    }

    private func uploadImages(images: [UIImage]) async throws -> [String] {
        var uploadedUrls: [String] = []
        let sellerId = Auth.auth().currentUser?.uid ?? "unknown_user"

        for image in images {
            guard let imageData = image.compressedJPEG() else {
                throw NSError(domain: "EditListingView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG data."])
            }

            let imageRef = storage.child("listing_images/\(sellerId)/\(UUID().uuidString).jpg")

            _ = try await imageRef.putDataAsync(imageData, metadata: nil)
            let downloadURL = try await imageRef.downloadURL()
            uploadedUrls.append(downloadURL.absoluteString)
        }
        return uploadedUrls
    }

    private func updateFirestore(with data: [String: Any]) async {
        guard let listingID = originalListing.id else {
            triggerAlert(title: "Update Error", message: "Original listing ID is missing. Cannot update.")
            isSaving = false
            return
        }

        do {
            try await db.collection("listings").document(listingID).updateData(data)

            var updatedListing = originalListing
            updatedListing.title = title
            updatedListing.price = Double(price) ?? originalListing.price
            updatedListing.description = listingDescription.isEmpty ? nil : listingDescription
            updatedListing.locationName = locationText.isEmpty ? nil : locationText
            updatedListing.latitude = currentLatitude
            updatedListing.longitude = currentLongitude
            updatedListing.category = selectedCategory
            updatedListing.timestamp = Date()
            updatedListing.imageUrls = finalImageUrlsToSave

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .listingUpdated, object: updatedListing)
                onSave?(updatedListing)
            }
            triggerAlert(title: "Success", message: "Listing updated successfully!")
            isSaving = false
            dismiss()
        } catch {
            triggerAlert(title: "Update Error", message: "Failed to update listing: \(error.localizedDescription)")
            isSaving = false
        }
    }

    private func triggerAlert(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }

    private func extractCityAndState(from address: String) async -> String {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            if let placemark = placemarks.first,
               let city = placemark.locality,
               let state = placemark.administrativeArea {
                return "\(city), \(state)"
            }
        } catch {
            print("Geocoding failed: \(error.localizedDescription)")
        }
        return address
    }
}
