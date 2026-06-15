import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background isolate handler — must be a top-level/`@pragma('vm:entry-point')`
/// function. For `notification` payloads FCM shows the system tray entry
/// automatically, so this only needs to (re)initialise Firebase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Remote push (FCM): registers the device token against the signed-in user so
/// the server can target them, and shows foreground messages as local
/// notifications. Sending is done server-side (see docs / a Cloud Function that
/// reads users/{uid}.fcmToken on budget-overrun / delay / milestone events).
class PushService {
  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'push_alerts',
    'Push Alerts',
    channelDescription: 'Budget, delay and milestone alerts',
    importance: Importance.max,
    priority: Priority.high,
  );

  static Future<void> init() async {
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _local.initialize(const InitializationSettings(android: android));

      // Foreground messages don't auto-display — show them ourselves.
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) {
          _show(n.title ?? 'ConstructIQ', n.body ?? '');
        }
      });

      // Register/refresh the device token for whoever is signed in.
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) _saveToken(user.uid);
      });
      _fm.onTokenRefresh.listen((token) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) _writeToken(uid, token);
      });
    } catch (e) {
      debugPrint('[PUSH] init failed: $e');
    }
  }

  static Future<void> _saveToken(String uid) async {
    try {
      final token = await _fm.getToken();
      if (token != null) _writeToken(uid, token);
    } catch (e) {
      debugPrint('[PUSH] token fetch failed: $e');
    }
  }

  static Future<void> _writeToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _show(String title, String body) async {
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: _androidDetails),
    );
  }
}
