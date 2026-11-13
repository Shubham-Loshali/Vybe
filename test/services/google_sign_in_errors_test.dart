import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/utilities/auth_error_messages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android developer error 10 explains the email alternative without internals', () {
    final message = googleSignInErrorMessage(
      PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      ),
    );
    expect(message, contains('sign up or log in with email'));
    expect(message, isNot(contains('PlatformException')));
    expect(message, isNot(contains('ApiException')));
  });

  test('network failures do not masquerade as configuration problems', () {
    for (final error in [
      PlatformException(code: 'network_error'),
      PlatformException(code: 'sign_in_failed', message: 'ApiException: 7: '),
      FirebaseAuthException(code: 'network-request-failed'),
    ]) {
      expect(
        googleSignInErrorMessage(error),
        contains('Check your connection'),
      );
    }
  });

  test('unknown failures never expose exception details', () {
    final message = googleSignInErrorMessage(
      PlatformException(
        code: 'sign_in_failed',
        message: 'private diagnostic details',
      ),
    );
    expect(message, contains('try again or use email'));
    expect(message, isNot(contains('private diagnostic details')));
  });

  test('Google configuration problems and cancelled sign-in reset state correctly', () async {
    const channel = MethodChannel('plugins.flutter.io/google_sign_in');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final service = CloudSyncService.instance;
    final configured = service.isFirebaseConfigured;
    final previousMessage = service.syncMessage.value;
    final previousState = service.syncState.value;
    Object? error = PlatformException(
      code: 'sign_in_failed',
      message: 'com.google.android.gms.common.api.ApiException: 10: ',
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'signIn' && error != null) throw error;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      service.isFirebaseConfigured = configured;
      service.syncMessage.value = previousMessage;
      service.syncState.value = previousState;
    });
    service.isFirebaseConfigured = true;
    expect(await service.signInWithGoogle(), isFalse);
    expect(service.syncState.value, CloudSyncState.error);
    expect(service.syncMessage.value, contains('sign up or log in with email'));

    // Cancelling after a failure must not bring back the previous error banner.
    error = null;
    expect(await service.signInWithGoogle(), isFalse);
    expect(service.syncState.value, CloudSyncState.idle);
    expect(service.syncMessage.value, isNull);

    error = PlatformException(code: 'sign_in_canceled');
    expect(await service.signInWithGoogle(), isFalse);
    expect(service.syncState.value, CloudSyncState.idle);
    expect(service.syncMessage.value, isNull);
  });
}
