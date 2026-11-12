import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vybe/localization/app_localizations.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/position_data.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/utilities/artwork_provider.dart';

class UiTestAudioHandler extends Fake implements VybeAudioHandler {
  @override
  final mediaItem = BehaviorSubject<MediaItem?>.seeded(null);
  @override
  final queue = BehaviorSubject<List<MediaItem>>.seeded([]);
  @override
  final playbackState = BehaviorSubject<PlaybackState>.seeded(
    PlaybackState(processingState: AudioProcessingState.ready),
  );
  final positions = BehaviorSubject<PositionData>.seeded(
    PositionData(Duration.zero, Duration.zero, const Duration(minutes: 3)),
  );
  @override
  Stream<PlaybackState> get playbackStateStream => playbackState.stream;
  @override
  Stream<PositionData> get positionDataStream => positions.stream;
  @override
  PositionData get currentPositionData => positions.value;
  @override
  Future<void> play() async => playbackState.add(
    PlaybackState(playing: true, processingState: AudioProcessingState.ready),
  );
  @override
  Future<void> pause() async => playbackState.add(
    PlaybackState(processingState: AudioProcessingState.ready),
  );
  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}
  Future<void> close() async {
    // A paused app-lifetime broadcast subscription can defer a subject's done
    // event. Close every input without waiting for that deferred event.
    unawaited(mediaItem.close());
    unawaited(queue.close());
    unawaited(playbackState.close());
    unawaited(positions.close());
  }
}

Future<Directory> openUiLibrary(UiTestAudioHandler handler) async {
  final directory = await Directory.systemTemp.createTemp('vybe-ui-test-');
  Hive.init(directory.path);
  await Future.wait(
    [
      'settings',
      'user',
      'userNoBackup',
      'cache',
    ].map((name) => Hive.openBox(name, bytes: Uint8List(0))),
  );
  audioHandler = handler;
  return directory;
}

Widget uiApp(Widget child, {double scale = 1, bool reduceMotion = false}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(body: child),
      ),
    );

Future<List<String>> makeCoverData() async {
  final result = <String>[];
  for (final color in [Colors.red, Colors.green, Colors.blue, Colors.orange]) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final image = await recorder.endRecording().toImage(8, 8);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    result.add(
      'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}',
    );
    image.dispose();
  }
  return result;
}

Future<void> warmArtwork(Iterable<String> sources) async {
  for (final source in sources) {
    final done = Completer<void>();
    final stream = ArtworkProvider.get(source)
        .resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (_, __) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      await done.future.timeout(const Duration(seconds: 3));
    } finally {
      stream.removeListener(listener);
    }
  }
}
