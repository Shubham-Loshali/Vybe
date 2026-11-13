import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class TestAccountUser extends Fake implements User {
  TestAccountUser({
    this.uid = 'test-account',
    this.displayName,
    this.email,
    this.emailVerified = true,
    this.isAnonymous = false,
  });

  @override
  final String uid;
  @override
  final String? displayName;
  @override
  final String? email;
  @override
  final bool emailVerified;
  @override
  final bool isAnonymous;
}
