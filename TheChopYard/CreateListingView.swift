import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import Contacts

@available(iOS 16.0, *)
struct CreateListingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var price = ""
    @State private var listingDescription = ""
    @State private var locationText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var uiImages: [UIImage] = []
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = "Error"
    @State private var isShowingLocationSearch = false
    @State private var selectedCategory: String = ""

    private let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private let db = Firestore.firestore()
    private let storage = Storage.storage().reference(forURL: "gs://the-chop-yard.firebasestorage.app")

    var body: some View {
        NavigationView {
            Form {
                detailsSection
                photoSection
                submitButtonSection
            }
            .navigationTitle("Create Listing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
        .onChange(of: selectedPhotoItems) { newItems in
            Task {
                var loadedImages: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let compressed = image.compressedJPEG() {
                        loadedImages.append(UIImage(data: compressed) ?? image)
                    }
                }
                uiImages = loadedImages
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if alertTitle == "Success" {
                    dismiss()
                }
            }
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
            categorySelectionSection
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

    private var categorySelectionSection: some View {
        VStack(alignment: .leading) {
            Picker("Category", selection: $selectedCategory) {
                Text("Select Category").tag("")
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)

            if selectedCategory.isEmpty && !isSubmitting {
                Text("Please select a category.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 2)
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Photos (First image is main)")) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                Label("Select up to 10 photos", systemImage: "photo.on.rectangle.angled")
            }

            if !uiImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack {
                        ForEach(Array(uiImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    Button {
                                        uiImages.remove(at: index)
                                        if index < selectedPhotoItems.count {
                                            selectedPhotoItems.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(4), alignment: .topTrailing
                                )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var submitButtonSection: some View {
        Section {
            Button(action: {
                hideKeyboard()
                validateAndSubmitListing()
            }) {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView().frame(height: 20)
                    } else {
                        Text("Submit Listing")
                    }
                    Spacer()
                }
            }
            .disabled(isSubmitting || !isFormValid())
        }
    }

    private func isFormValid() -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Double(price) ?? -1) > 0 &&
        !listingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !locationText.isEmpty && selectedCoordinate != nil &&
        !uiImages.isEmpty &&
        !selectedCategory.isEmpty
    }

    private func validateAndSubmitListing() {
        guard Auth.auth().currentUser?.uid != nil else {
            triggerAlert(title: "Authentication Error", message: "You must be logged in to create a listing.")
            return
        }

        Task {
            await submitListing()
        }
    }

    private func submitListing() async {
        isSubmitting = true
        guard let coordinate = selectedCoordinate, let sellerId = Auth.auth().currentUser?.uid else {
            triggerAlert(title: "Error", message: "User or location missing.")
            isSubmitting = false
            return
        }

        do {
            let uploadedImageUrls = try await uploadImages(images: uiImages, sellerIdForPath: sellerId)
            let listing: [String: Any] = [
                "title": title,
                "price": Double(price)!,
                "description": listingDescription,
                "locationName": locationText,
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "imageUrls": uploadedImageUrls,
                "sellerId": sellerId,
                "category": selectedCategory,
                "timestamp": FieldValue.serverTimestamp(),
                "viewCount": 0,
                "saveCount": 0
            ]
            try await db.collection("listings").addDocument(data: listing)
            triggerAlert(title: "Success", message: "Listing submitted successfully!")
            resetForm()
        } catch {
            triggerAlert(title: "Submission Error", message: "Error: \(error.localizedDescription)")
        }
        isSubmitting = false
    }

    private func uploadImages(images: [UIImage], sellerIdForPath: String) async throws -> [String] {
        var uploadedUrls: [String] = []
        for image in images {
            guard let imageData = image.compressedJPEG() else {
                throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Compression failed."])
            }

            let imageName = UUID().uuidString + ".jpg"
            let imageRef = storage.child("listing_images/\(sellerIdForPath)/\(imageName)")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            do {
                _ = try await imageRef.putDataAsync(imageData, metadata: metadata)
            } catch {
                throw error
            }

            let url = try await imageRef.downloadURL()
            uploadedUrls.append(url.absoluteString)
        }
        return uploadedUrls
    }

    private func resetForm() {
        title = ""
        price = ""
        listingDescription = ""
        locationText = ""
        selectedCoordinate = nil
        selectedPhotoItems = []
        uiImages = []
        selectedCategory = ""
    }

    private func triggerAlert(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
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
        return ""
    }
}

extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension UIImage {
    func compressedJPEG(quality: CGFloat = 0.6, maxSize: CGFloat = 800) -> Data? {
        let resized = self.scaledToMaxSize(maxSize: maxSize)
        return resized.jpegData(compressionQuality: quality)
    }

    func scaledToMaxSize(maxSize: CGFloat) -> UIImage {
        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if aspectRatio > 1 {
            newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
