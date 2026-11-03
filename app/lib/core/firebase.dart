import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'env.dart';

/// Every callable runs here (docs/FIREBASE.md D1).
const functionsRegion = 'asia-south1';

/// The emulator suite's host as the phone sees it: 127.0.0.1 on a USB phone after `adb reverse tcp:9099 tcp:9099`
/// (and 8080, 5001, 9199), or `--dart-define=EMULATOR_HOST=10.0.2.2` on the Android emulator image.
const emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');

/// The project the build talks to. The emulators only accept their demo project, which can never reach real data.
/// shortcut: from the FIREBASE_* dart-defines until `flutterfire configure` writes firebase_options.dart (owner step).
FirebaseOptions get firebaseOptions => useEmulators
    ? const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:000000000000:android:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-shyam-mobiles',
        storageBucket: 'demo-shyam-mobiles.appspot.com',
      )
    : const FirebaseOptions(
        apiKey: Env.firebaseApiKey,
        appId: Env.firebaseAppId,
        messagingSenderId: Env.firebaseMessagingSenderId,
        projectId: Env.firebaseProjectId,
        storageBucket: '${Env.firebaseProjectId}.firebasestorage.app',
      );

/// Starts Firebase for BACKEND=firebase, before runApp: the app, App Check, the emulators, and Analytics' consent
/// defaults (docs/SECURITY.md §2.1, §4.3).
Future<void> initFirebase() async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
  if (useEmulators) {
    // The demo project has no App Check backend to mint tokens, and the emulators don't ask for them.
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    FirebaseFunctions.instanceFor(region: functionsRegion).useFunctionsEmulator(emulatorHost, 5001);
    await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
  } else {
    // Play Integrity in release and profile builds; the debug provider (tokens registered in the console) only in
    // debug builds, where kDebugMode is a compile-time true.
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
    );
  }
  // Ads stay off for good. Collection itself starts off (AndroidManifest.xml) until [setAnalyticsConsent].
  await FirebaseAnalytics.instance.setConsent(
    adStorageConsentGranted: false,
    adUserDataConsentGranted: false,
    adPersonalizationSignalsConsentGranted: false,
  );
}

/// The customer's "Help improve the app" choice (Account → Privacy, docs/SECURITY.md §4.2). Firebase remembers it on
/// the phone; withdrawing also wipes this install's analytics data.
Future<void> setAnalyticsConsent(bool granted) async {
  final analytics = FirebaseAnalytics.instance;
  await analytics.setConsent(
    analyticsStorageConsentGranted: granted,
    adStorageConsentGranted: false,
    adUserDataConsentGranted: false,
    adPersonalizationSignalsConsentGranted: false,
  );
  await analytics.setAnalyticsCollectionEnabled(granted);
  if (!granted) await analytics.resetAnalyticsData();
}

// The SDK entry points, as providers so Firebase repositories take them from ref and tests can swap them.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final functionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: functionsRegion));
final storageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);
