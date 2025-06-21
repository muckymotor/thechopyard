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
                Section(header: Text("Details")) {
                    TextField("Title", text: $title)
                    TextField("Price", text: $price).keyboardType(.decimalPad)
                    TextField("Description", text: $listingDescription, axis: .vertical).lineLimit(3...6)
                    locationField
                    categoryPicker
                }

                Section(header: Text("Photos")) {
                    PhotosPicker(selection: $newSelectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                        Text("Select New Photos (replaces all)")
                    }
                    photoSectionContent
                }

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
                newUiImages = await loadImages(from: newSelectedPhotoItems)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var locationField: some View {
        HStack {
            Text(locationText.isEmpty ? "Select Location" : locationText)
                .foregroundColor(locationText.isEmpty ? Color(UIColor.placeholderText) : .primary)
            Spacer()
            Button { isShowingLocationSearch = true } label: {
                Image(systemName: "map.fill")
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading) {
            Picker("Category", selection: $selectedCategory) {
                Text("Select Category").tag("")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)

            if selectedCategory.isEmpty && !isSaving {
                Text("Please select a category.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private var photoSectionContent: some View {
        if !newUiImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(newUiImages.enumerated()), id: \.offset) { _, image in
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

    private func validateAndSaveChanges() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            triggerAlert(title: "Validation Error", message: "Title cannot be empty.")
            return
        }

        guard let priceValue = Double(price), priceValue > 0 else {
            triggerAlert(title: "Validation Error", message: "Invalid price.")
            return
        }

        guard selectedCoordinate != nil else {
            triggerAlert(title: "Validation Error", message: "Location is missing.")
            return
        }

        guard !selectedCategory.isEmpty else {
            triggerAlert(title: "Validation Error", message: "Please select a category.")
            return
        }

        Task { await saveChanges() }
    }

    private func saveChanges() async {
        isSaving = true
        var finalImageUrls = originalListing.imageUrls

        if !newUiImages.isEmpty {
            for url in existingImageUrls {
                if let path = try? Storage.storage().reference(forURL: url).fullPath {
                    try? await Storage.storage().reference(withPath: path).delete()
                }
            }

            do {
                finalImageUrls = try await uploadImages(images: newUiImages)
            } catch {
                triggerAlert(title: "Upload Error", message: error.localizedDescription)
                isSaving = false
                return
            }
        }

        let updatedData: [String: Any] = [
            "title": title,
            "price": Double(price) ?? originalListing.price,
            "description": listingDescription.isEmpty ? NSNull() : listingDescription,
            "locationName": locationText.isEmpty ? NSNull() : locationText,
            "latitude": selectedCoordinate?.latitude ?? originalListing.latitude,
            "longitude": selectedCoordinate?.longitude ?? originalListing.longitude,
            "sellerId": originalListing.sellerId,
            "category": selectedCategory,
            "timestamp": FieldValue.serverTimestamp(),
            "imageUrls": finalImageUrls
        ]

        await updateFirestore(updatedData: updatedData, finalImageUrls: finalImageUrls)
    }

    private func updateFirestore(updatedData: [String: Any], finalImageUrls: [String]) async {
        guard let listingID = originalListing.id else {
            triggerAlert(title: "Update Error", message: "Missing listing ID.")
            isSaving = false
            return
        }

        do {
            let docRef = db.collection("listings").document(listingID)
            try await docRef.updateData(updatedData)

            let snapshot = try await docRef.getDocument()
            if let updated = try? snapshot.data(as: Listing.self) {
                DispatchQueue.main.async {
                    appViewModel.updateListing(updated)
                    NotificationCenter.default.post(name: .listingUpdated, object: listingID)
                    onSave?(updated)
                    dismiss()
                }
            } else {
                triggerAlert(title: "Update Error", message: "Failed to decode updated listing.")
            }
        } catch {
            triggerAlert(title: "Firestore Error", message: error.localizedDescription)
        }

        isSaving = false
    }

    private func uploadImages(images: [UIImage]) async throws -> [String] {
        var urls: [String] = []
        let userId = Auth.auth().currentUser?.uid ?? "unknown_user"

        for image in images {
            guard let data = image.compressedJPEG() else {
                throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }

            let ref = storage.child("listing_images/\(userId)/\(UUID().uuidString).jpg")
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            urls.append(url.absoluteString)
        }

        return urls
    }

    private func loadImages(from items: [PhotosPickerItem]) async -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let compressed = image.compressedJPEG() {
                images.append(UIImage(data: compressed) ?? image)
            }
        }
        return images
    }

    private func triggerAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
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
            print("Geocoding failed: \(error)")
        }
        return address
    }
}
