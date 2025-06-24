const functions = require("firebase-functions"); // ✅ Use v1-style for auth triggers
const admin = require("firebase-admin");

admin.initializeApp();


exports.cleanUpUserData = functions.auth.user().onDelete(async (user) => {
  const uid = user.uid;
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  console.log(`Starting cleanup for user ${uid}`);

  const listingsSnapshot = await db.collection("listings").where("sellerId", "==", uid).get();
  const deleteTasks = [];

  for (const doc of listingsSnapshot.docs) {
    const data = doc.data();
    const imageUrls = data.imageUrls || [];

    const imageDeletions = imageUrls.map((url) => {
      try {
        const path = decodeURIComponent(new URL(url).pathname.split("/o/")[1].split("?")[0]).replace(/%2F/g, "/");
        return bucket.file(path).delete().catch(err => console.warn("Image delete failed:", err.message));
      } catch {
        return Promise.resolve();
      }
    });

    deleteTasks.push(...imageDeletions, doc.ref.delete());
  }

  const chatsSnapshot = await db.collection("chats").where("participants", "array-contains", uid).get();
  for (const chatDoc of chatsSnapshot.docs) {
    const data = chatDoc.data();
    const chatRef = chatDoc.ref;

    const remainingParticipants = (data.participants || []).filter(id => id !== uid);
    const remainingVisibleTo = (data.visibleTo || []).filter(id => id !== uid);

    if (remainingParticipants.length === 0) {
      const messagesSnapshot = await chatRef.collection("messages").get();
      const msgDeletes = messagesSnapshot.docs.map(msg => msg.ref.delete());
      deleteTasks.push(...msgDeletes, chatRef.delete());
    } else {
      deleteTasks.push(chatRef.update({
        participants: remainingParticipants,
        visibleTo: remainingVisibleTo
      }));
    }
  }

  deleteTasks.push(db.collection("users").doc(uid).delete());

  const usernamesSnapshot = await db.collection("usernames").where("uid", "==", uid).get();
  for (const doc of usernamesSnapshot.docs) {
    deleteTasks.push(doc.ref.delete());
  }

  await Promise.all(deleteTasks);
  console.log(`Cleanup complete for user ${uid}`);
});

exports.notifyNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const chatId = context.params.chatId;

    const chatDoc = await admin.firestore().collection('chats').doc(chatId).get();
    const participants = chatDoc.data().participants || [];
    const senderId = message.senderId;

    const recipientIds = participants.filter((id) => id !== senderId);
    const tokens = [];

    for (const uid of recipientIds) {
      const userDoc = await admin.firestore().collection('users').doc(uid).get();
      const userTokens = userDoc.data().fcmTokens || [];
      tokens.push(...userTokens);
    }

    if (tokens.length === 0) return null;

    const payload = {
      notification: {
        title: chatDoc.data().listingTitle || 'New Message',
        body: message.text,
      },
      data: {
        chatId,
      },
    };

    return admin.messaging().sendToDevice(tokens, payload);
  });
