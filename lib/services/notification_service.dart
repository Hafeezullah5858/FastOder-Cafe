import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String uid) =>
      _db.collection('notifications').where('recipientId', isEqualTo: uid).snapshots();

  Future<void> markRead(String id) =>
      _db.collection('notifications').doc(id).update({'read': true});

  /// Registers the device for real push notifications. The token is stored only
  /// on the signed-in user's own document; it is not treated as an authorization token.
  Future<void> initializePushNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _db.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null || newToken.isEmpty) return;
      await _db.collection('users').doc(current.uid).set({
        'fcmToken': newToken,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background data messages can be handled here if server payloads require it.
}
