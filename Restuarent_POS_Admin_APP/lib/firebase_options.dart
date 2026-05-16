import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const String webClientId =
      '531957308412-2lgpspvuj7f3jims5uisfvevau7ocali.apps.googleusercontent.com';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase is configured for Android and web in this project.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCsAtPPVd6kM2ee2sDg75cN4OzatTTwpyc',
    appId: '1:531957308412:web:283934b92b5569a59e7079',
    messagingSenderId: '531957308412',
    projectId: 'pos-restaurent-terabyte-ai',
    authDomain: 'pos-restaurent-terabyte-ai.firebaseapp.com',
    storageBucket: 'pos-restaurent-terabyte-ai.firebasestorage.app',
    measurementId: 'G-MG5L3MXVJ6',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBH_yKmUS6T0p-c_wKV1IAbMMZv1yVZvlo',
    appId: '1:531957308412:android:8aa49b5926cafb129e7079',
    messagingSenderId: '531957308412',
    projectId: 'pos-restaurent-terabyte-ai',
    storageBucket: 'pos-restaurent-terabyte-ai.firebasestorage.app',
  );
}
