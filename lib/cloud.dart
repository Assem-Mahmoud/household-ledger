// Optional Google sign-in with a cloud copy of the user's data (Firebase Auth + Firestore).
// The cloud copy is the normal backup minus the raw SMS texts, gzip-compressed and split into
// Firestore documents under users/{uid}/ (each user can only read and write their own).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'state.dart';

/// OAuth "Web client ID" of the Firebase project (Authentication → Google → Web SDK configuration).
const webClientId = String.fromEnvironment('WEB_CLIENT_ID', defaultValue: '931030887336-kbg4toucr7fup56gqkmtmu4kfk2ancg7.apps.googleusercontent.com');

class Cloud {
  static bool ready = false;
  static final user = ValueNotifier<User?>(null);
  static final busy = ValueNotifier<bool>(false);

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
      user.value = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((u) => user.value = u);
    } catch (_) {
      ready = false; // no Firebase config in this build
    }
  }

  static bool get signedIn => user.value != null;
  static String get email => user.value?.email ?? '';
  static String get name => user.value?.displayName ?? '';

  /// Returns null on success, otherwise a message to show.
  static Future<String?> signIn() async {
    if (!ready) return 'Cloud sign-in is not set up in this version yet.';
    try {
      final g = GoogleSignIn(scopes: const ['email'], serverClientId: webClientId.isEmpty ? null : webClientId);
      final acc = await g.signIn();
      if (acc == null) return ''; // cancelled
      final auth = await acc.authentication;
      await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken));
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  static DocumentReference<Map<String, dynamic>> get _meta =>
      FirebaseFirestore.instance.collection('users').doc(user.value!.uid);

  static const _chunk = 700000; // characters per Firestore document (limit is 1 MiB)

  /// Uploads a fresh cloud copy. Returns true on success.
  static Future<bool> backup() async {
    if (!ready || !signedIn) return false;
    busy.value = true;
    try {
      final json = await app.backupJson(forCloud: true);
      final packed = base64Encode(GZipCodec().encode(utf8.encode(json)));
      final parts = <String>[for (var i = 0; i < packed.length; i += _chunk) packed.substring(i, i + _chunk > packed.length ? packed.length : i + _chunk)];
      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();
      for (var i = 0; i < parts.length; i++) {
        batch.set(_meta.collection('backup').doc('part$i'), {'data': parts[i]});
      }
      batch.set(_meta, {
        'parts': parts.length,
        'entries': app.txns.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'app': 'shahri',
      });
      await batch.commit();
      await app.setSetting('cloudBackupAt', '${DateTime.now().millisecondsSinceEpoch}');
      return true;
    } catch (_) {
      return false;
    } finally {
      busy.value = false;
    }
  }

  /// When the cloud copy was made and how many entries it holds, or null if there is none.
  static Future<(DateTime?, int)?> info() async {
    if (!ready || !signedIn) return null;
    try {
      final d = await _meta.get();
      if (!d.exists) return null;
      final m = d.data()!;
      return ((m['updatedAt'] as Timestamp?)?.toDate(), (m['entries'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// Replaces the app's data with the cloud copy. Returns null on success, otherwise what went wrong.
  static Future<String?> restore() async {
    if (!ready || !signedIn) return 'Not signed in.';
    busy.value = true;
    try {
      final m = (await _meta.get()).data();
      if (m == null) return 'No cloud backup yet.';
      final n = (m['parts'] as num).toInt();
      final sb = StringBuffer();
      for (var i = 0; i < n; i++) {
        sb.write((await _meta.collection('backup').doc('part$i').get()).data()?['data'] ?? '');
      }
      final json = utf8.decode(GZipCodec().decode(base64Decode(sb.toString())));
      final d = jsonDecode(json);
      if (d is! Map || d['app'] != 'household_ledger') return 'The cloud copy could not be read.';
      await app.restoreBackup(json);
      return null;
    } catch (e) {
      return '$e';
    } finally {
      busy.value = false;
    }
  }

  /// Daily cloud copy, run when the app opens.
  static Future<void> autoBackupIfDue() async {
    if (!ready || !signedIn || app.txns.isEmpty) return;
    final ms = int.tryParse(app.settings['cloudBackupAt'] ?? '');
    if (ms != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inHours < 20) return;
    await backup();
  }
}
