import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MessagesView: View {
    @State private var chatThreads: [ChatThread] = []
    private let db = Firestore.firestore()
    @State private var listener: ListenerRegistration?

    var body: some View {
        NavigationView {
            Group {
                if chatThreads.isEmpty {
                    VStack {
                        Spacer()
                        Text("No conversations yet")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(chatThreads) { thread in
                            NavigationLink(destination: ChatView(chatId: thread.id, sellerUsername: thread.displayName)) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 40, height: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(thread.displayName)
                                            .font(.headline)
                                        Text(thread.lastMessage)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(thread.timestamp.relativeTimeString())
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: hideChatThread)
                    }
                    .refreshable {
                        fetchChatsOnce()
                    }
                }
            }
            .navigationTitle("Messages")
            .onAppear {
                listenForChatUpdates()
            }
            .onDisappear {
                listener?.remove()
            }
        }
    }

    private func listenForChatUpdates() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        listener?.remove() // Remove any previous listener
        listener = db.collection("chats")
            .whereField("visibleTo", arrayContains: currentUserId)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }

                var fetchedThreads: [ChatThread] = []
                let dispatchGroup = DispatchGroup()

                for doc in docs {
                    let data = doc.data()
                    let participants = data["participants"] as? [String] ?? []
                    let lastMessage = data["lastMessage"] as? String ?? ""
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()

                    guard !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }

                    let otherUserId = participants.first { $0 != currentUserId } ?? "Unknown"

                    dispatchGroup.enter()
                    db.collection("users").document(otherUserId).getDocument { userSnapshot, _ in
                        let userData = userSnapshot?.data()
                        let username = userData?["username"] as? String ?? "Unknown"

                        let thread = ChatThread(
                            id: doc.documentID,
                            displayName: username,
                            lastMessage: lastMessage,
                            timestamp: timestamp
                        )

                        fetchedThreads.append(thread)
                        dispatchGroup.leave()
                    }
                }

                dispatchGroup.notify(queue: .main) {
                    self.chatThreads = fetchedThreads
                }
            }
    }

    private func fetchChatsOnce() {
        listener?.remove()
        listenForChatUpdates()
    }

    private func hideChatThread(at offsets: IndexSet) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        for index in offsets {
            let thread = chatThreads[index]
            let chatRef = db.collection("chats").document(thread.id)

            chatRef.updateData([
                "visibleTo": FieldValue.arrayRemove([currentUserId])
            ]) { error in
                if let error = error {
                    print("Error hiding chat: \(error.localizedDescription)")
                }
            }
        }

        chatThreads.remove(atOffsets: offsets)
    }
}

struct ChatThread: Identifiable {
    let id: String
    let displayName: String
    let lastMessage: String
    let timestamp: Date
}
