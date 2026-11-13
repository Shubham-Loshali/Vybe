import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/utilities/auth_error_messages.dart';
import 'package:vybe/widgets/auth_dialog.dart';

import '../support/ui_fixture.dart';

class TestAuthService extends Fake implements CloudSyncService {
  @override
  final syncMessage = ValueNotifier<String?>(null);
  final signUps = <(String, String)>[];
  final signIns = <(String, String)>[];
  final resets = <String>[];
  int googleCalls = 0;
  Completer<bool>? pendingGoogle;
  bool shouldSucceed = true;

  @override
  Future<bool> signUpWithEmail(String email, String password) async {
    signUps.add((email, password));
    return shouldSucceed;
  }

  @override
  Future<bool> signInWithEmail(String email, String password) async {
    signIns.add((email, password));
    return shouldSucceed;
  }

  @override
  Future<bool> sendPasswordReset(String email) async {
    resets.add(email);
    return shouldSucceed;
  }

  @override
  Future<bool> signInWithGoogle() async {
    googleCalls++;
    return pendingGoogle?.future ?? shouldSucceed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = UiTestAudioHandler();
  final captureKey = GlobalKey();
  late Directory directory;
  late TestAuthService service;

  setUpAll(() async {
    directory = await openUiLibrary(audio);
    final fonts = FontLoader('Figtree');
    for (final weight in [
      '400Regular',
      '500Medium',
      '600SemiBold',
      '700Bold',
      '800ExtraBold',
    ]) {
      fonts.addFont(
        rootBundle.load('assets/fonts/figtree/Figtree_$weight.ttf'),
      );
    }
    await fonts.load();
    await (FontLoader('paytoneOne')..addFont(
          rootBundle.load('assets/fonts/paytone/PaytoneOne-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    service = TestAuthService();
  });

  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> openAuth(
    WidgetTester tester, {
    bool signUp = true,
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboardHeight = 0,
    bool usePublicEntry = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getAppTheme(getAppColorScheme(null, null)),
        builder: (context, child) => RepaintBoundary(
          key: captureKey,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  if (usePublicEntry) {
                    unawaited(
                      AuthDialog.show(context, initiallySignUp: signUp),
                    );
                  } else {
                    unawaited(
                      showDialog<void>(
                        context: context,
                        useSafeArea: false,
                        barrierDismissible: false,
                        builder: (_) => AuthDialog(
                          initiallySignUp: signUp,
                          service: service,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Open account'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/vybe_icon.png'),
        captureKey.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('AUTH_PREVIEW_DIR');
    if (output.isEmpty) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'account entry fills the screen and offers the existing sign-up methods',
    (tester) async {
      await openAuth(tester);
      expect(tester.getSize(find.byType(Dialog)), const Size(390, 844));
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
      await capture(tester, 'signup');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching modes preserves credentials and re-hides the password',
    (tester) async {
      await openAuth(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'sasha@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        ' password ',
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('auth-password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      await tapVisible(tester, find.widgetWithText(TextButton, 'Log in'));
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.first.controller!.text, 'sasha@example.com');
      expect(fields.last.controller!.text, ' password ');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('auth-password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      expect(find.text('Forgot password?'), findsOneWidget);
      await capture(tester, 'login');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validates fields, then creates an account and explains email verification',
    (tester) async {
      await openAuth(tester);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(service.signUps, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, 'sasha@invalid');
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        '123',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(service.signUps, isEmpty);
      await tester.enterText(
        find.byType(TextFormField).first,
        ' sasha@example.com ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        ' password ',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );
      expect(service.signUps.single, ('sasha@example.com', ' password '));
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
        find.textContaining('verify your email, then log in.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
      await tester.ensureVisible(find.text('Check your inbox'));
      await tester.pumpAndSettle();
      await capture(tester, 'verification');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Log in'));
      expect(service.signIns.single, ('sasha@example.com', ' password '));
      expect(find.byType(AuthDialog), findsNothing);
    },
  );

  testWidgets(
    'password reset validates only the email and keeps the login flow',
    (tester) async {
      await openAuth(tester, signUp: false);
      await tapVisible(tester, find.text('Forgot password?'));
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(service.resets, isEmpty);
      await tester.enterText(
        find.byType(TextFormField).first,
        'sasha@example.com',
      );
      await tapVisible(tester, find.text('Forgot password?'));
      expect(service.resets.single, 'sasha@example.com');
      expect(find.textContaining('password reset link'), findsOneWidget);
      expect(find.text('Enter your password.'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    },
  );

  testWidgets(
    'Google sign-in blocks duplicate submissions and recovers after cancellation',
    (tester) async {
      service.pendingGoogle = Completer<bool>();
      await openAuth(tester);
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(service.googleCalls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Skip for now'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<PopScope>(find.byType(PopScope).first).canPop,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AuthDialog), findsOneWidget);
      service.pendingGoogle!.complete(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.text('Let’s try that again'), findsNothing);
    },
  );

  testWidgets(
    'Google setup errors keep email sign-up available without technical text',
    (tester) async {
      service.shouldSucceed = false;
      service.syncMessage.value = googleSignInErrorMessage(
        PlatformException(
          code: 'sign_in_failed',
          message: 'com.google.android.gms.common.api.ApiException: 10: ',
        ),
      );
      await openAuth(tester);
      await tapVisible(tester, find.text('Continue with Google'));
      expect(
        find.textContaining('sign up or log in with email'),
        findsOneWidget,
      );
      expect(find.textContaining('ApiException'), findsNothing);
      await tester.ensureVisible(find.text('Let’s try that again'));
      await tester.pumpAndSettle();
      await capture(tester, 'google-configuration-error');
      service.shouldSucceed = true;
      await tester.enterText(
        find.byType(TextFormField).first,
        'sasha@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'password',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create account'),
      );
      expect(service.signUps.single, ('sasha@example.com', 'password'));
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.text('Let’s try that again'), findsNothing);
    },
  );

  testWidgets('service errors stay visible and allow another attempt', (
    tester,
  ) async {
    service.shouldSucceed = false;
    service.syncMessage.value = 'Please check your connection and try again.';
    await openAuth(tester);
    await tapVisible(tester, find.text('Continue with Google'));
    expect(find.text('Let’s try that again'), findsOneWidget);
    expect(
      find.text('Please check your connection and try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Let’s try that again'));
    await tester.pumpAndSettle();
    await capture(tester, 'error');
  });

  testWidgets(
    'small screens, the keyboard, and large text keep every action reachable',
    (tester) async {
      await openAuth(
        tester,
        size: const Size(320, 568),
        scale: 1.8,
        keyboardHeight: 250,
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'sasha@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'password',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Log in'));
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'skip remembers the preference and dismisses the public account screen',
    (tester) async {
      await Hive.box('settings').delete('auth_prompt_dismissed');
      await openAuth(tester, usePublicEntry: true);
      await tester.tap(find.text('Skip for now'));
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(Hive.box('settings').get('auth_prompt_dismissed'), isTrue);
      expect(find.byType(AuthDialog), findsNothing);
      expect(find.text('Open account'), findsOneWidget);
    },
  );
}
