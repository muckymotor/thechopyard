import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let text: String
    let senderId: String
    let timestamp: Date
}

@MainActor
struct ChatView: View {
    let chatId: String
    let sellerUsername: String
    let otherUserId: String

    @EnvironmentObject var appViewModel: AppViewModel
    @State private var messages: [Message] = []
    @State private var newMessage = ""
    @State private var listener: ListenerRegistration?

    private var db: Firestore { Firestore.firestore() }
    private var currentUserId: String? { appViewModel.user?.uid }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            HStack(alignment: .bottom, spacing: 8) {
                                if message.senderId == currentUserId {
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(message.text)
                                            .padding(12)
                                            .contextMenu {
                                                Button("Copy") {
                                                    UIPasteboard.general.string = message.text
                                                }
                                            }
                                            .background(Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(16)
                                        Text(shortTimestamp(message.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.text)
                                            .padding(12)
                                            .contextMenu {
                                                Button("Copy") {
                                                    UIPasteboard.general.string = message.text
                                                }
                                            }
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(16)
                                        Text(shortTimestamp(message.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.vertical)
                    .padding(.horizontal, 12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Message...", text: $newMessage, axis: .vertical)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .lineLimit(1...4)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .padding(10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(sellerUsername)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            listenToMessages()
            markChatAsRead()
        }
        .onDisappear {
            listener?.remove()
        }
    }

    private func listenToMessages() {
        listener?.remove()
        guard let currentUserId else { return }

        listener = db.collection("chats").document(chatId)
            .collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs.compactMap { try? $0.data(as: Message.self) }
                self.markChatAsRead()
            }
    }

    private func sendMessage() {
        guard let currentUserId else { return }
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = Message(id: nil, text: trimmed, senderId: currentUserId, timestamp: Date())
        let messageRef = db.collection("chats").document(chatId).collection("messages").document()
        let chatRef = db.collection("chats").document(chatId)

        do {
            try messageRef.setData(from: message)
            chatRef.updateData([
                "lastMessage": message.text,
                "lastMessageTimestamp": message.timestamp,
                "lastMessageSenderId": currentUserId,
                "readBy": [currentUserId],
                "visibleTo": FieldValue.arrayUnion([currentUserId, otherUserId])
            ])
            newMessage = ""
        } catch {
            print("Failed to send message: \(error.localizedDescription)")
        }
    }

    private func markChatAsRead() {
        guard let currentUserId else { return }
        let chatRef = db.collection("chats").document(chatId)
        chatRef.updateData([
            "readBy": FieldValue.arrayUnion([currentUserId])
        ])
    }

    private func shortTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
