import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/position_data.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/artwork_provider.dart';
import 'package:vybe/widgets/now_playing/spotify_lyrics_card.dart';

class TestAudioHandler extends Fake implements VybeAudioHandler {
  TestAudioHandler(MediaItem first) : mediaItem = BehaviorSubject.seeded(first);
  @override
  final BehaviorSubject<MediaItem?> mediaItem;
  @override
  final BehaviorSubject<PlaybackState> playbackState = BehaviorSubject.seeded(
    PlaybackState(),
  );
  final positions = BehaviorSubject<PositionData>.seeded(
    PositionData(
      const Duration(seconds: 15),
      Duration.zero,
      const Duration(seconds: 210),
    ),
  );
  @override
  Stream<PositionData> get positionDataStream => positions.stream;
  @override
  PositionData get currentPositionData => positions.value;
  @override
  Future<void> seek(Duration position) async => positions.add(
    PositionData(position, Duration.zero, const Duration(seconds: 210)),
  );
  @override
  Future<void> play() async => playbackState.add(PlaybackState(playing: true));
  @override
  Future<void> pause() async => playbackState.add(PlaybackState());
  Future<void> close() async {
    await mediaItem.close();
    await playbackState.close();
    await positions.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestAudioHandler handler;
  late MediaItem first;
  late MediaItem second;
  final captureKey = GlobalKey();
  const lines = [
    'Let the city lights fade slowly',
    'Hear the rhythm in the rain',
    'Every echo brings me closer',
    'We are brighter than the night',
    'Stay until the morning finds us',
    'Let the music take us home',
  ];

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vybe-lyrics-player-');
    Hive.init(directory.path);
    await Future.wait(
      ['settings', 'user', 'userNoBackup', 'cache'].map(Hive.openBox),
    );
    final fonts = FontLoader('Figtree');
    for (final weight in [
      '400Regular',
      '600SemiBold',
      '700Bold',
      '800ExtraBold',
    ]) {
      fonts.addFont(
        rootBundle.load('assets/fonts/figtree/Figtree_$weight.ttf'),
      );
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // A self-contained abstract cover keeps tests independent of the network.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, 512, 512);
    canvas
      ..drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEF9D61), Color(0xFF853C74), Color(0xFF14243B)],
          ).createShader(bounds),
      )
      ..drawCircle(
        const Offset(256, 230),
        146,
        Paint()..color = const Color(0x55FFE3BB),
      )
      ..drawCircle(
        const Offset(302, 194),
        120,
        Paint()..color = const Color(0xFF853C74),
      );
    final image = await recorder.endRecording().toImage(512, 512);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${directory.path}/cover.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    first = MediaItem(
      id: 'first',
      title: 'Afterglow',
      artist: 'Vybe Studio',
      duration: const Duration(seconds: 210),
      artUri: Uri.file('${directory.path}/cover.png'),
    );
    second = const MediaItem(
      id: 'second',
      title: 'Another song',
      artist: 'Another artist',
      duration: Duration(seconds: 180),
    );
  });

  setUp(() async {
    ArtworkProvider.clearCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    offlineMode.value = true;
    syncedLyricsEnabled.value = true;
    handler = TestAudioHandler(first);
    audioHandler = handler;
    await saveCustomSongLyrics(
      Lyrics(
        source: 'Local file',
        synced: [
          for (var i = 0; i < lines.length; i++)
            LyricLine(Duration(seconds: i * 5), lines[i]),
        ],
      ),
      first.artist,
      first.title,
    );
    await saveCustomSongLyrics(
      const Lyrics(source: 'Local file', plain: 'Words for the next song'),
      second.artist,
      second.title,
    );
  });
  tearDown(() async {
    await handler.close();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget app() => MaterialApp(
    theme: ThemeData.dark().copyWith(
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Figtree'),
    ),
    builder: (context, child) => RepaintBoundary(key: captureKey, child: child),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SpotifyLyricsCard(
          metadata: first,
          dominantColor: const Color(0xFFAF694B),
        ),
      ),
    ),
  );

  Future<void> pumpPlayer(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app());
      await precacheImage(
        FileImage(File(first.artUri!.toFilePath())),
        captureKey.currentContext!,
      );
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('LYRICS_PREVIEW_DIR');
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
    'expanded lyrics follow queue changes and retain plain fallback',
    (tester) async {
      await pumpPlayer(tester);
      await tester.tap(find.byTooltip('Expand lyrics'));
      await tester.pumpAndSettle();
      expect(find.text('Afterglow'), findsOneWidget);
      handler.mediaItem.add(second);
      await tester.pumpAndSettle();
      expect(find.text('Another song'), findsOneWidget);
      expect(find.text('Words for the next song'), findsOneWidget);
      expect(find.text('Lyrics without timing'), findsOneWidget);
      expect(find.text('Afterglow'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('portrait player remains readable on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPlayer(tester);
    await capture(tester, 'lyrics-card');
    await tester.tap(find.byTooltip('Expand lyrics'));
    await tester.pumpAndSettle();
    expect(find.text('Timing 0.0s'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'lyrics-portrait');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape shows cover and lyrics without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Expand lyrics'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'lyrics-landscape');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
