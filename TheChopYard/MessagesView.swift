import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatThread: Identifiable, Equatable, Hashable {
    let id: String
    var displayName: String
    var lastMessage: String
    var lastMessageTimestamp: Date
    var othersellerId: String
    var listingTitle: String?
    var listingImageUrl: String?
    var readBy: [String]
    var lastMessageSenderId: String

    var displayLastMessage: String {
        lastMessage.isEmpty ? "No messages yet." : lastMessage
    }

    func isUnread(for currentsellerId: String) -> Bool {
        return !readBy.contains(currentsellerId) && lastMessageSenderId != currentsellerId
    }
}

struct ChatThreadRow: View {
    let thread: ChatThread
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 10, height: 10)
            }

            if let imageUrl = thread.listingImageUrl,
               let url = URL(string: imageUrl),
               !imageUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Image(systemName: "photo.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.gray)
                    } else {
                        Color.gray.opacity(0.1).overlay(ProgressView())
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(thread.displayLastMessage)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            Text(thread.lastMessageTimestamp, style: .time)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

@MainActor
struct MessagesView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var chatThreads: [ChatThread] = []
    @State private var isLoading = false
    @State private var listener: ListenerRegistration?
    @State private var navigationPath = NavigationPath()

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading && chatThreads.isEmpty {
                    ProgressView("Loading conversations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chatThreads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "message.badge.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Conversations Yet")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("When you message a seller, your chats will appear here.")
                            .font(.callout)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(chatThreads) { thread in
                            NavigationLink(value: thread) {
                                ChatThreadRow(thread: thread, isUnread: thread.isUnread(for: appViewModel.user?.uid ?? ""))
                            }
                        }
                        .onDelete(perform: hideChatThread)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        do {
                            async let refreshChats: () = listenForChatUpdates(forceRefresh: true)
                            async let delay: () = try Task.sleep(nanoseconds: 500_000_000)
                            _ = try await (refreshChats, delay)
                        } catch {
                            print("MessagesView: Error during refresh delay: \(error.localizedDescription)")
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationDestination(for: ChatThread.self) { thread in
                ChatView(chatId: thread.id, sellerUsername: thread.displayName)
                    .environmentObject(appViewModel)
            }
            .onAppear {
                Task { await listenForChatUpdates() }
            }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
        }
    }

    private func listenForChatUpdates(forceRefresh: Bool = false) async {
        guard let currentsellerId = appViewModel.user?.uid else {
            chatThreads = []
            isLoading = false
            return
        }

        if listener != nil && !forceRefresh && !isLoading {
            return
        }

        isLoading = true
        listener?.remove()

        listener = db.collection("chats")
            .whereField("visibleTo", arrayContains: currentsellerId)
            .order(by: "lastMessageTimestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                Task {
                    if let error = error {
                        print("MessagesView: Listener error: \(error.localizedDescription)")
                        self.isLoading = false
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        self.chatThreads = []
                        self.isLoading = false
                        return
                    }

                    var fetchedThreads: [ChatThread] = []
                    var hasUnread = false

                    for doc in documents {
                        let data = doc.data()
                        let participants = data["participants"] as? [String] ?? []
                        let lastMessage = data["lastMessage"] as? String ?? ""
                        let timestamp = (data["lastMessageTimestamp"] as? Timestamp)?.dateValue() ?? Date()
                        let listingTitle = data["listingTitle"] as? String
                        let listingImageUrl = data["listingImageUrl"] as? String
                        let readBy = data["readBy"] as? [String] ?? []
                        let lastMessageSenderId = data["lastMessageSenderId"] as? String ?? ""

                        let othersellerId = participants.first { $0 != currentsellerId } ?? "unknown"
                        guard othersellerId != "unknown" else { continue }

                        var displayName = "Unknown User"
                        if let names = data["participantNames"] as? [String: String],
                           let name = names[othersellerId] {
                            displayName = name
                        }

                        let thread = ChatThread(
                            id: doc.documentID,
                            displayName: displayName,
                            lastMessage: lastMessage,
                            lastMessageTimestamp: timestamp,
                            othersellerId: othersellerId,
                            listingTitle: listingTitle,
                            listingImageUrl: listingImageUrl,
                            readBy: readBy,
                            lastMessageSenderId: lastMessageSenderId
                        )

                        if thread.isUnread(for: currentsellerId) {
                            hasUnread = true
                        }

                        fetchedThreads.append(thread)
                    }

                    self.chatThreads = fetchedThreads.sorted(by: { $0.lastMessageTimestamp > $1.lastMessageTimestamp })
                    self.appViewModel.hasUnreadMessages = hasUnread
                    self.isLoading = false
                }
            }
    }

    private func hideChatThread(at offsets: IndexSet) {
        guard let currentsellerId = appViewModel.user?.uid else { return }
        let toHide = offsets.map { chatThreads[$0] }
        chatThreads.remove(atOffsets: offsets)

        for thread in toHide {
            let ref = db.collection("chats").document(thread.id)
            ref.updateData([
                "visibleTo": FieldValue.arrayRemove([currentsellerId])
            ]) { error in
                if let error = error {
                    print("Error hiding chat \(thread.id): \(error.localizedDescription)")
                }
            }
        }
    }
}
