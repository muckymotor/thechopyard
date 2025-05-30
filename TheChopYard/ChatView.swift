import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ChatView: View {
    let chatId: String
    let sellerUsername: String

    @State private var messages: [Message] = []
    @State private var newMessageText: String = ""

    private let db = Firestore.firestore()

    var body: some View {
        VStack {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            HStack {
                                if message.senderId == Auth.auth().currentUser?.uid {
                                    Spacer()
                                    MessageBubble(message: message.text, timestamp: message.timestamp, isCurrentUser: true)
                                } else {
                                    MessageBubble(message: message.text, timestamp: message.timestamp, isCurrentUser: false)
                                    Spacer()
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .onChange(of: messages.count) { _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Type a message...", text: $newMessageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minHeight: 30)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                }
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(sellerUsername)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadMessages)
    }

    private func loadMessages() {
        db.collection("chats").document(chatId).collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs.compactMap { doc in
                    let data = doc.data()
                    return Message(
                        id: doc.documentID,
                        text: data["text"] as? String ?? "",
                        senderId: data["senderId"] as? String ?? "",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
            }
    }

    private func sendMessage() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let trimmedText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let messageData: [String: Any] = [
            "text": trimmedText,
            "senderId": userId,
            "timestamp": Timestamp()
        ]

        let chatRef = db.collection("chats").document(chatId)

        chatRef.collection("messages").addDocument(data: messageData) { error in
            if error == nil {
                newMessageText = ""

                // Update chat metadata
                chatRef.updateData([
                    "lastMessage": trimmedText,
                    "timestamp": Timestamp(),
                    "visibleTo": FieldValue.arrayUnion([userId]) // Ensure sender sees the thread
                ]) { err in
                    if let err = err {
                        print("Error updating chat metadata: \(err.localizedDescription)")
                    }
                }
            } else {
                print("Failed to send message: \(error!.localizedDescription)")
            }
        }
    }
}

struct MessageBubble: View {
    let message: String
    let timestamp: Date
    let isCurrentUser: Bool

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
            Text(message)
                .padding(10)
                .background(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isCurrentUser ? .white : .primary)
                .cornerRadius(12)

            Text(timestamp.relativeTimeString())
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: 250, alignment: isCurrentUser ? .trailing : .leading)
    }
}

struct Message: Identifiable {
    let id: String
    let text: String
    let senderId: String
    let timestamp: Date
}
