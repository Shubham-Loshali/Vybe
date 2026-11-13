import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/support.dart';
import 'package:vybe/localization/app_localizations.dart';
import 'package:vybe/screens/developers_page.dart';
import 'package:vybe/screens/settings_page.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/widgets/coffee_support_sheet.dart';

import '../support/ui_fixture.dart';

class _DevelopersTestBinding extends AutomatedTestWidgetsFlutterBinding {
  // Keep the green glows visible in device previews.
  @override
  bool get disableShadows => false;
}

void main() {
  _DevelopersTestBinding();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final audio = UiTestAudioHandler();
  final captureKey = GlobalKey();
  final launches = <MethodCall>[];
  late Directory directory;
  var launchResult = true;
  String? copiedText;

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
    for (final style in ['Regular', 'Filled']) {
      await (FontLoader(
            'packages/fluentui_system_icons/FluentSystemIcons-$style',
          )..addFont(
            rootBundle.load(
              'packages/fluentui_system_icons/fonts/FluentSystemIcons-$style.ttf',
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    launches.clear();
    copiedText = null;
    launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launches.add(call);
          return launchResult;
        }
        return false;
      })
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': copiedText};
        return null;
      });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(SystemChannels.platform, null);
  });

  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget wrap(Widget child, {double scale = 1}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    theme: getAppTheme(getAppColorScheme(null, null)),
    builder: (context, child) => RepaintBoundary(
      key: captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
    home: child,
  );

  Future<void> openPage(
    WidgetTester tester, {
    double scale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const DevelopersPage(), scale: scale));
    await tester.runAsync(() async {
      for (final asset in [
        'headphones.png',
        'github.png',
        'deepak.png',
        'shubham.png',
      ]) {
        await precacheImage(
          AssetImage('assets/images/developers/$asset'),
          tester.element(find.byType(DevelopersPage)),
        );
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('DEVELOPERS_PREVIEW_DIR');
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

  test(
    'UPI request keeps the supplied recipient and leaves the amount editable',
    () {
      final uri = coffeePaymentUri();
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'ddumka102@okhdfcbank');
      expect(uri.queryParameters['pn'], 'Deepak Dumka');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters.containsKey('am'), isFalse);
      expect(uri.toString(), contains('Deepak%20Dumka'));
    },
  );

  testWidgets('developer links open the exact profiles supplied by the owner', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.text('Deepak Dumka'), findsOneWidget);
    expect(find.text('Shubham Loshali'), findsOneWidget);
    await capture(tester, 'developers');
    for (final index in [0, 1]) {
      await tapVisible(
        tester,
        find.widgetWithText(TextButton, 'GitHub').at(index),
      );
      await tapVisible(
        tester,
        find.widgetWithText(TextButton, 'LinkedIn').at(index),
      );
    }
    expect(launches.map((call) => (call.arguments as Map)['url']).toList(), [
      'https://github.com/Deepakdumka1',
      'https://www.linkedin.com/in/deepakdumka',
      'https://github.com/Shubham-Loshali',
      'https://www.linkedin.com/in/shubham-loshali',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coffee shows the UPI ID, copies it, and opens a generic UPI request',
    (tester) async {
      await openPage(tester);
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Buy us a coffee'),
      );
      expect(find.byType(CoffeeSupportSheet), findsOneWidget);
      expect(find.text('ddumka102@okhdfcbank'), findsOneWidget);
      await capture(tester, 'coffee-payment');
      await tapVisible(tester, find.text('Copy UPI ID'));
      expect(copiedText, 'ddumka102@okhdfcbank');
      expect(find.text('UPI ID copied'), findsOneWidget);
      await tapVisible(tester, find.text('Open UPI app'));
      expect(launches, hasLength(1));
      final arguments = launches.single.arguments as Map;
      final uri = Uri.parse(arguments['url'] as String);
      expect(uri.queryParameters['pa'], 'ddumka102@okhdfcbank');
      expect(uri.queryParameters.containsKey('am'), isFalse);
      expect(arguments['useWebView'], isFalse);
      expect(find.text('Payment successful'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a missing UPI app keeps the copy option available', (
    tester,
  ) async {
    launchResult = false;
    await openPage(tester);
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Buy us a coffee'),
    );
    await tapVisible(tester, find.text('Open UPI app'));
    expect(find.textContaining('Couldn’t open a UPI app.'), findsOneWidget);
    await tapVisible(tester, find.text('Copy UPI ID'));
    expect(copiedText, 'ddumka102@okhdfcbank');
    expect(find.text('Payment successful'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings opens Developers from the top-right action and supports back navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsPage(),
            routes: [
              GoRoute(
                path: 'developers',
                builder: (_, __) => const DevelopersPage(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          theme: getAppTheme(getAppColorScheme(null, null)),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byTooltip('Developers & support');
      expect(tester.getTopRight(action).dx, greaterThan(300));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(DevelopersPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'developer cards and payment options stay reachable on a small screen at both text sizes',
    (tester) async {
      for (final scale in [1.0, 1.8]) {
        await openPage(tester, scale: scale, size: const Size(320, 568));
        await capture(tester, 'developers-small-$scale');
        for (final index in [0, 1]) {
          await tapVisible(
            tester,
            find.widgetWithText(TextButton, 'GitHub').at(index),
          );
          await tapVisible(
            tester,
            find.widgetWithText(TextButton, 'LinkedIn').at(index),
          );
        }
        await tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Buy us a coffee'),
        );
        await tester.ensureVisible(find.text('Copy UPI ID'));
        await tester.pumpAndSettle();
        expect(find.text('ddumka102@okhdfcbank'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('Copy UPI ID'));
        expect(copiedText, 'ddumka102@okhdfcbank');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
