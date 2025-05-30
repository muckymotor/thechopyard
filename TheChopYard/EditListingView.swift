import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

@available(iOS 16.0, *)
struct EditListingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appViewModel: AppViewModel

    private var originalListing: Listing

    @State private var title: String
    @State private var price: String
    @State private var listingDescription: String
    @State private var locationText: String
    @State private var selectedCategory: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    @State private var existingImageUrls: [String]
    @State private var newSelectedPhotoItems: [PhotosPickerItem] = []
    @State private var newUiImages: [UIImage] = []

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private let db = Firestore.firestore()
    private let storage = Storage.storage().reference()

    var onSave: (() -> Void)?

    init(listing: Listing, onSave: (() -> Void)? = nil) {
        self.originalListing = listing
        self.onSave = onSave

        _title = State(initialValue: listing.title)
        _price = State(initialValue: String(format: "%.2f", listing.price))
        _listingDescription = State(initialValue: listing.description ?? "")
        _locationText = State(initialValue: listing.locationName ?? "")
        _selectedCategory = State(initialValue: listing.category ?? "")
        _selectedCoordinate = State(initialValue: listing.location.coordinate)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertMessage.contains("successfully") ? "Success" : "Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onChange(of: newSelectedPhotoItems) { _ in
                Task {
                    var loadedImages: [UIImage] = []
                    for item in newSelectedPhotoItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            loadedImages.append(image)
                        }
                    }
                    newUiImages = loadedImages
                }
            }
        }
    }

    private var detailsSection: some View {
        Section(header: Text("Details")) {
            TextField("Title", text: $title)
            TextField("Price", text: $price).keyboardType(.decimalPad)
            TextField("Description", text: $listingDescription, axis: .vertical).lineLimit(3...6)
            TextField("Location", text: $locationText).disabled(true)

            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }

            if selectedCategory.isEmpty {
                Text("Please select a category.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var photoSection: some View {
        Section(header: Text("Update Photos")) {
            PhotosPicker(selection: $newSelectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                Text("Select New Photos (replaces all existing)")
            }

            if !newUiImages.isEmpty {
                Text("New Images Preview:").font(.caption)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(newUiImages, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }.padding(.top, 8)
                }
            } else if !existingImageUrls.isEmpty {
                Text("Current Images:").font(.caption)
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
                    }.padding(.top, 8)
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
            alertMessage = "Title cannot be empty."
            showAlert = true
            return
        }
        guard let _ = Double(price) else {
            alertMessage = "Invalid price."
            showAlert = true
            return
        }

        Task {
            await saveChanges()
        }
    }

    private func saveChanges() async {
        isSaving = true

        var finalImageUrls: [String] = originalListing.imageUrls
        var finalAspectRatios: [CGFloat]? = originalListing.imageAspectRatios

        if !newUiImages.isEmpty {
            do {
                finalImageUrls = try await uploadImages(images: newUiImages)
                finalAspectRatios = newUiImages.map { $0.size.width / $0.size.height }
            } catch {
                alertMessage = "Error uploading new images: \(error.localizedDescription)"
                showAlert = true
                isSaving = false
                return
            }
        }

        var updatedData: [String: Any] = [
            "title": title,
            "price": Double(price) ?? originalListing.price,
            "description": listingDescription,
            "locationName": locationText,
            "latitude": selectedCoordinate?.latitude ?? originalListing.location.coordinate.latitude,
            "longitude": selectedCoordinate?.longitude ?? originalListing.location.coordinate.longitude,
            "sellerId": originalListing.sellerId,
            "category": selectedCategory,
            "timestamp": Timestamp(date: Date()),
            "imageUrls": finalImageUrls,
            "imageAspectRatios": finalAspectRatios ?? []
        ]

        await updateFirestore(with: updatedData)
    }

    private func uploadImages(images: [UIImage]) async throws -> [String] {
        var uploadedUrls: [String] = []
        for image in images {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "EditListingView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data."])
            }

            let imageRef = storage.child("listing_images/\(UUID().uuidString).jpg")

            try await imageRef.putDataAsync(imageData)
            let downloadURL = try await imageRef.downloadURL()
            uploadedUrls.append(downloadURL.absoluteString)
        }
        return uploadedUrls
    }

    private func updateFirestore(with data: [String: Any]) async {
        do {
            try await db.collection("listings").document(originalListing.id).updateData(data)
            alertMessage = "Listing updated successfully!"
            showAlert = true
            isSaving = false
            onSave?()
            dismiss()
        } catch {
            alertMessage = "Failed to update listing: \(error.localizedDescription)"
            showAlert = true
            isSaving = false
        }
    }
}
