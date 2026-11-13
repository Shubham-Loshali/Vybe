import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/library_merge_service.dart';
import 'package:vybe/utilities/auth_error_messages.dart';

enum CloudSyncState { idle, syncing, success, error }

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  bool isFirebaseConfigured = false;
  final ValueNotifier<User?> currentUser = ValueNotifier<User?>(null);
  final ValueNotifier<CloudSyncState> syncState =
      ValueNotifier<CloudSyncState>(CloudSyncState.idle);
  final ValueNotifier<DateTime?> lastSyncedAt =
      ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> syncMessage = ValueNotifier<String?>(null);

  StreamSubscription<BoxEvent>? _userBoxSubscription;
  Timer? _debounceTimer;
  bool _isDisposed = false;

  /// Initializes Firebase and sets up auth / storage listeners.
  Future<void> initialise() async {
    try {
      await Firebase.initializeApp();
      isFirebaseConfigured = true;

      // Restore last synced timestamp from local settings
      final savedTime = Hive.box('settings').get('cloudLastSyncedAt');
      if (savedTime is String) {
        lastSyncedAt.value = DateTime.tryParse(savedTime);
      }

      FirebaseAuth.instance.userChanges().listen((user) {
        final previousUid = currentUser.value?.uid;
        if (user != null && !user.emailVerified) {
          currentUser.value = null;
          _stopWatchingLocalChanges();
          return;
        }
        currentUser.value = user;
        if (user == null) {
          _stopWatchingLocalChanges();
        } else if (user.uid != previousUid) {
          // Profile updates refresh the greeting without re-importing a library.
          unawaited(syncFromCloud());
          _startWatchingLocalChanges();
        }
      });
      logger.log('Firebase CloudSyncService initialised successfully');
    } catch (e) {
      // Firebase not configured yet (e.g. awaiting google-services.json)
      isFirebaseConfigured = false;
      logger.log('Firebase initialization skipped or pending setup: $e');
    }
  }

  /// Sign in using Google Account
  Future<bool> signInWithGoogle() async {
    if (!isFirebaseConfigured) {
      syncState.value = CloudSyncState.error;
      syncMessage.value =
          'Account sign-in isn’t available right now. Please try again later.';
      return false;
    }
    syncMessage.value = null;
    syncState.value = CloudSyncState.syncing;
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        syncState.value = CloudSyncState.idle;
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      syncState.value = CloudSyncState.success;
      syncMessage.value = 'Signed in as ${googleUser.email}';
      return true;
    } catch (e, stackTrace) {
      logger.log('Google Sign-In failed', error: e, stackTrace: stackTrace);
      final message = googleSignInErrorMessage(e);
      syncState.value =
          message == null ? CloudSyncState.idle : CloudSyncState.error;
      syncMessage.value = message;
      return false;
    }
  }

  /// Sign in using Email and Password (requires verified email)
  Future<bool> signInWithEmail(String email, String password) async {
    if (!isFirebaseConfigured) {
      syncMessage.value = 'Firebase is not yet configured.';
      return false;
    }
    syncState.value = CloudSyncState.syncing;
    try {
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await user.reload();
        if (!user.emailVerified) {
          try {
            await user.sendEmailVerification();
          } catch (_) {}
          await FirebaseAuth.instance.signOut();
          currentUser.value = null;
          syncState.value = CloudSyncState.error;
          syncMessage.value =
              'Email not verified. We sent a verification link to $email. Please check your inbox and verify before signing in.';
          return false;
        }
      }

      syncState.value = CloudSyncState.success;
      syncMessage.value = 'Signed in successfully';
      return true;
    } on FirebaseAuthException catch (e) {
      syncState.value = CloudSyncState.error;
      syncMessage.value = e.message ?? e.code;
      return false;
    } catch (e) {
      syncState.value = CloudSyncState.error;
      syncMessage.value = e.toString();
      return false;
    }
  }

  /// Register a new account using Email and Password and send verification email
  Future<bool> signUpWithEmail(String email, String password) async {
    if (!isFirebaseConfigured) {
      syncMessage.value = 'Firebase is not yet configured.';
      return false;
    }
    syncState.value = CloudSyncState.syncing;
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await user.sendEmailVerification();
        await FirebaseAuth.instance.signOut();
        currentUser.value = null;
      }

      syncState.value = CloudSyncState.idle;
      syncMessage.value =
          'Verification email sent to $email. Please check your inbox (and spam folder) to verify before signing in.';
      return true;
    } on FirebaseAuthException catch (e) {
      syncState.value = CloudSyncState.error;
      syncMessage.value = e.message ?? e.code;
      return false;
    } catch (e) {
      syncState.value = CloudSyncState.error;
      syncMessage.value = e.toString();
      return false;
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordReset(String email) async {
    if (!isFirebaseConfigured) {
      syncMessage.value = 'Firebase is not yet configured.';
      return false;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      syncMessage.value = 'Password reset email sent to $email';
      return true;
    } on FirebaseAuthException catch (e) {
      syncMessage.value = e.message ?? e.code;
      return false;
    } catch (e) {
      syncMessage.value = e.toString();
      return false;
    }
  }

  /// Sign out of current account
  Future<void> signOut() async {
    _stopWatchingLocalChanges();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    if (isFirebaseConfigured) {
      await FirebaseAuth.instance.signOut();
    }
    currentUser.value = null;
    syncState.value = CloudSyncState.idle;
    syncMessage.value = null;
  }

  /// Upload current local library state to Firestore
  Future<bool> syncToCloud() async {
    final user = currentUser.value;
    if (!isFirebaseConfigured || user == null) return false;

    syncState.value = CloudSyncState.syncing;
    try {
      final payload = await LibraryMergeService.exportLibrary();
      final payloadJson = jsonEncode(payload);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'schemaVersion': payload['schemaVersion'],
        'email': user.email,
        'payloadJson': payloadJson,
      }, SetOptions(merge: true));

      final now = DateTime.now();
      lastSyncedAt.value = now;
      await Hive.box('settings').put('cloudLastSyncedAt', now.toIso8601String());

      syncState.value = CloudSyncState.success;
      syncMessage.value = 'Synced with cloud';
      return true;
    } catch (e, stackTrace) {
      logger.log('Failed to upload library to cloud',
          error: e, stackTrace: stackTrace);
      syncState.value = CloudSyncState.error;
      syncMessage.value = 'Sync failed: $e';
      return false;
    }
  }

  /// Download and merge library state from Firestore into local Hive
  Future<bool> syncFromCloud() async {
    final user = currentUser.value;
    if (!isFirebaseConfigured || user == null) return false;

    syncState.value = CloudSyncState.syncing;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        // First time user signs in: upload local library to cloud
        logger.log('No cloud backup found. Uploading local library to cloud...');
        return await syncToCloud();
      }

      final data = doc.data()!;
      final payloadJson = data['payloadJson'] as String?;

      if (payloadJson != null && payloadJson.isNotEmpty) {
        final remotePayload =
            jsonDecode(payloadJson) as Map<String, dynamic>;
        final mergeResult =
            await LibraryMergeService.mergeLibrary(remotePayload);

        // If local had changes or merge resolved conflicts, push back merged copy
        if (mergeResult.changed.isNotEmpty) {
          unawaited(syncToCloud());
        }
      }

      final now = DateTime.now();
      lastSyncedAt.value = now;
      await Hive.box('settings').put('cloudLastSyncedAt', now.toIso8601String());

      syncState.value = CloudSyncState.success;
      syncMessage.value = 'Synced with cloud';
      return true;
    } catch (e, stackTrace) {
      logger.log('Failed to download library from cloud',
          error: e, stackTrace: stackTrace);
      syncState.value = CloudSyncState.error;
      syncMessage.value = 'Download failed: $e';
      return false;
    }
  }

  /// Watches local Hive changes and debounces automatic cloud sync
  void _startWatchingLocalChanges() {
    _stopWatchingLocalChanges();
    _userBoxSubscription = Hive.box('user').watch().listen((event) {
      final key = event.key.toString();

      // Don't sync writes performed by the merge itself
      if (LibraryMergeService.isMergeWrite(key, event.value)) return;

      // Check if key belongs to one of the syncable categories
      final isSyncable =
          syncCategoryKeys.values.any((keys) => keys.contains(key));
      if (!isSyncable) return;

      // 4-second debounce to batch multiple updates into a single free write
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 4), () {
        if (!_isDisposed && currentUser.value != null && isFirebaseConfigured) {
          unawaited(syncToCloud());
        }
      });
    });
  }

  void _stopWatchingLocalChanges() {
    _debounceTimer?.cancel();
    _userBoxSubscription?.cancel();
    _userBoxSubscription = null;
  }

  void dispose() {
    _isDisposed = true;
    _stopWatchingLocalChanges();
  }
}
