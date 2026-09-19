import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Allows Flutter Web, Android, and iOS to initialize Firebase cleanly.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBKLlfqQESubM-6thV44W8e1yhdLDKo6ds',
    appId: '1:999147799724:web:12bad74bc073f9ea708b09',
    messagingSenderId: '999147799724',
    projectId: 'aacr-a86dc',
    authDomain: 'aacr-a86dc.firebaseapp.com',
    storageBucket: 'aacr-a86dc.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBKLlfqQESubM-6thV44W8e1yhdLDKo6ds',
    appId: '1:999147799724:android:12bad74bc073f9ea708b09',
    messagingSenderId: '999147799724',
    projectId: 'aacr-a86dc',
    storageBucket: 'aacr-a86dc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBKLlfqQESubM-6thV44W8e1yhdLDKo6ds',
    appId: '1:999147799724:ios:12bad74bc073f9ea708b09',
    messagingSenderId: '999147799724',
    projectId: 'aacr-a86dc',
    storageBucket: 'aacr-a86dc.firebasestorage.app',
  );
}
