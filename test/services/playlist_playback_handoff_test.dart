import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// The platform interface lets the real handler and just_audio run without Android.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    directory = await Directory.systemTemp.createTemp('vybe-handoff-');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          null,
        );
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'Android task removal stops the loaded player and media service state',
    () async {
      final manifest = await File('android/app/src/main/AndroidManifest.xml')
          .readAsString();
      final audioService = RegExp(
        r'<service\b[^>]*android:name="com\.ryanheise\.audioservice\.AudioService"[^>]*>',
      ).firstMatch(manifest)?.group(0);
      expect(audioService, contains('android:stopWithTask="false"'));
      final originalPlatform = JustAudioPlatform.instance;
      final platform = _PlaybackPlatform();
      JustAudioPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final audio = VybeAudioHandler();
      addTearDown(() async {
        await audio.stop();
        await audio.audioPlayer.dispose();
        JustAudioPlatform.instance = originalPlatform;
        debugDefaultTargetPlatformOverride = null;
      });
      const id = 'task-removal-track';
      const url = 'https://example.com/task-removal-track.m4a';
      await addOrUpdateData(
        'cache',
        'song_${id}_${audioQualitySetting.value}_url',
        url,
      );
      final started = platform.started.first;
      await audio.playResumableSong({'ytid': id, 'title': 'Task removal'});
      expect(await started, url);
      expect(platform.audibleSource, url);
      await audio.onTaskRemoved();
      expect(platform.audibleSource, isNull);
      expect(audio.playbackState.value.playing, isFalse);
      expect(
        audio.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
    },
  );

  test(
    'System media Stop dismisses a paused track and allows in-app resume',
    () async {
      final originalPlatform = JustAudioPlatform.instance;
      final platform = _PlaybackPlatform();
      JustAudioPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final audio = VybeAudioHandler();
      addTearDown(() async {
        await audio.stop();
        await audio.audioPlayer.dispose();
        JustAudioPlatform.instance = originalPlatform;
        debugDefaultTargetPlatformOverride = null;
      });
      const id = 'media-card-stop-track';
      const url = 'https://example.com/media-card-stop-track.m4a';
      await addOrUpdateData(
        'cache',
        'song_${id}_${audioQualitySetting.value}_url',
        url,
      );
      final started = platform.started.first;
      await audio.playResumableSong({'ytid': id, 'title': 'Media card'});
      expect(await started, url);
      await audio.pause();
      expect(await audio.getChildren(AudioService.recentRootId), hasLength(1));

      final stopping = audio.stop();
      expect(audio.playbackState.value.processingState, AudioProcessingState.idle);
      expect(audio.playbackState.value.controls, isEmpty);
      expect(audio.playbackState.value.systemActions, isEmpty);
      await stopping;
      expect(platform.audibleSource, isNull);
      expect(await audio.getChildren(AudioService.recentRootId), isEmpty);
      expect(audio.queue.value, hasLength(1));

      final resumed = platform.started.first;
      await audio.play();
      expect(await resumed, url);
      expect(await audio.getChildren(AudioService.recentRootId), hasLength(1));
      final state = await audio.playbackState
          .firstWhere((state) => state.playing)
          .timeout(const Duration(seconds: 2));
      expect(state.controls, contains(MediaControl.stop));
    },
  );

  test(
    'System media Stop cancels a track loading in the background',
    () async {
      final originalPlatform = JustAudioPlatform.instance;
      final platform = _PlaybackPlatform();
      JustAudioPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final audio = VybeAudioHandler();
      final gate = platform.loadGate = Completer<void>();
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await audio.stop();
        await audio.audioPlayer.dispose();
        JustAudioPlatform.instance = originalPlatform;
        debugDefaultTargetPlatformOverride = null;
      });
      const id = 'media-card-loading-track';
      const url = 'https://example.com/media-card-loading-track.m4a';
      await addOrUpdateData(
        'cache',
        'song_${id}_${audioQualitySetting.value}_url',
        url,
      );
      final requested = platform.loading.first;
      final loading = audio.playResumableSong({'ytid': id, 'title': 'Loading'});
      expect(await requested, url);

      final stopping = audio.stop();
      gate.complete();
      await Future.wait([loading, stopping]);
      expect(platform.audibleSource, isNull);
      expect(audio.playbackState.value.playing, isFalse);
      expect(audio.playbackState.value.controls, isEmpty);
      expect(await audio.getChildren(AudioService.recentRootId), isEmpty);
    },
  );

  test(
    'stream lookup overlaps the pause and shares an in-flight validation',
    () async {
      final originalPlatform = JustAudioPlatform.instance;
      final platform = _PlaybackPlatform();
      JustAudioPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final audio = VybeAudioHandler();
      final pause = Completer<void>();
      final validate = Completer<http.Response>();
      final validationStarted = Completer<void>();
      final initialQuality = audioQualitySetting.value;
      addTearDown(() async {
        if (!pause.isCompleted) pause.complete();
        if (!validate.isCompleted) validate.complete(http.Response('', 200));
        await audio.stop();
        await audio.audioPlayer.dispose();
        JustAudioPlatform.instance = originalPlatform;
        debugDefaultTargetPlatformOverride = null;
        audioQualitySetting.value = initialQuality;
      });
      const first = 'overlap-first';
      const second = 'overlap-second';
      final quality = audioQualitySetting.value;
      final nextKey = 'song_${second}_${quality}_url';
      final alternateQuality = quality == 'low' ? 'high' : 'low';
      final alternateKey = 'song_${second}_${alternateQuality}_url';
      const alternateUrl = 'https://example.com/overlap-second-alternate.m4a';
      const nextUrl = 'https://example.com/overlap-second.m4a';
      await addOrUpdateData(
        'cache',
        'song_${first}_${quality}_url',
        'https://example.com/overlap-first.m4a',
      );
      await addOrUpdateData('cache', nextKey, nextUrl);
      await addOrUpdateData('cache', alternateKey, alternateUrl);
      await Hive.box('cache').put(
        '${nextKey}_date',
        DateTime.now().subtract(const Duration(minutes: 75)),
      );
      final firstStarted = platform.started.first;
      await audio.playResumableSong({'ytid': first, 'title': 'First'});
      await firstStarted;

      var validations = 0;
      await http.runWithClient(
        () async {
          platform.pauseGate = pause;
          final nextStarted = platform.started.first;
          final switching = audio.playResumableSong({
            'ytid': second,
            'title': 'Second',
          });
          await validationStarted.future.timeout(const Duration(seconds: 2));
          expect(audio.mediaItem.value?.extras?['ytid'], first);
          final concurrentLookup = fetchSongStreamUrl(second, false);
          validate.complete(http.Response('', 200));
          expect(await concurrentLookup, nextUrl);
          expect(validations, 1);
          expect(audio.mediaItem.value?.extras?['ytid'], first);
          audioQualitySetting.value = alternateQuality;
          pause.complete();
          await switching;
          expect(await nextStarted, nextUrl);
          expect(audio.mediaItem.value?.extras?['ytid'], second);
          await Future<void>.delayed(Duration.zero);
          expect(Hive.box('cache').get(alternateKey), alternateUrl);
        },
        () => MockClient((request) {
          expect(request.method, 'HEAD');
          expect(request.url.toString(), nextUrl);
          validations++;
          if (!validationStarted.isCompleted) validationStarted.complete();
          return validate.future;
        }),
      );
    },
  );

  for (final (description, completes, prefersQueue) in [
    ('Next plays from autoplay', false, false),
    ('autoplay advances at completion', true, false),
    ('a song manually queued during lookup takes priority', false, true),
  ]) {
    test(description, () async {
      final originalPlatform = JustAudioPlatform.instance;
      final platform = _PlaybackPlatform();
      JustAudioPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final previousAutoplay = playNextSongAutomatically.value;
      final previousRepeat = repeatNotifier.value;
      playNextSongAutomatically.value = true;
      repeatNotifier.value = AudioServiceRepeatMode.none;
      final seed = {'ytid': 'autoplay-seed', 'title': 'Seed'};
      final next = {'ytid': 'autoplay-next', 'title': 'Related'};
      final queued = {'ytid': 'user-queued', 'title': 'Queued'};
      final expected = prefersQueue ? queued : next;
      final requested = Completer<void>();
      final recommendation = Completer<Map<String, dynamic>?>();
      final audio = VybeAudioHandler(
        findSimilarSong: (id, {excludedYtIds = const {}}) {
          if (id != seed['ytid']) return Future.value();
          expect(excludedYtIds, contains(id));
          requested.complete();
          return recommendation.future;
        },
      );
      addTearDown(() async {
        if (!recommendation.isCompleted) recommendation.complete();
        await audio.stop();
        await audio.audioPlayer.dispose();
        playNextSongAutomatically.value = previousAutoplay;
        repeatNotifier.value = previousRepeat;
        debugDefaultTargetPlatformOverride = null;
        JustAudioPlatform.instance = originalPlatform;
      });
      for (final song in [seed, expected]) {
        final id = song['ytid'];
        await addOrUpdateData(
          'cache',
          'song_${id}_${audioQualitySetting.value}_url',
          'https://example.com/$id.m4a',
        );
      }
      final firstStarted = platform.started.first;
      await audio.playResumableSong(seed);
      await firstStarted;
      await requested.future.timeout(const Duration(seconds: 4));
      expect(audio.canSkipToNext, isTrue);
      expect(audio.queue.value, hasLength(1));
      offlineMode.value = true;
      expect(audio.canSkipToNext, isFalse);
      offlineMode.value = false;
      playNextSongAutomatically.value = false;
      expect(audio.canSkipToNext, isFalse);
      playNextSongAutomatically.value = true;
      final secondStarted = platform.started.first;
      if (completes) {
        platform.players.values.single.publish(
          ProcessingStateMessage.completed,
        );
      } else {
        unawaited(audio.skipToNext());
      }
      if (prefersQueue) await audio.addToQueue(queued);
      recommendation.complete(next);
      expect(
        await secondStarted.timeout(const Duration(seconds: 4)),
        'https://example.com/${expected['ytid']}.m4a',
      );
      expect(audio.mediaItem.value?.extras?['ytid'], expected['ytid']);
      expect(audio.queue.value, hasLength(2));
    });
  }

  for (final downloaded in [false, true]) {
    final kind = downloaded ? 'downloaded' : 'collaborative';
    test(
      '$kind playlist switches source before publishing the new track',
      () async {
        final originalPlatform = JustAudioPlatform.instance;
        final platform = _PlaybackPlatform();
        JustAudioPlatform.instance = platform;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final audio = VybeAudioHandler();
        addTearDown(() async {
          await audio.stop();
          await audio.audioPlayer.dispose();
          debugDefaultTargetPlatformOverride = null;
          JustAudioPlatform.instance = originalPlatform;
          offlineMode.value = false;
        });
        offlineMode.value = downloaded;

        final songs = <Map<String, dynamic>>[];
        final sources = <String>[];
        for (final number in [1, 2]) {
          final id = '$kind-track-$number';
          final song = <String, dynamic>{
            'ytid': id,
            'title': 'Track $number',
            'highResImage': 'https://example.com/$id.jpg',
          };
          if (downloaded) {
            final file = await File('${directory.path}/$id.m4a')
                .writeAsBytes([number]);
            song['audioPath'] = file.path;
            sources.add(file.uri.toString());
          } else {
            final url = 'https://example.com/$id.m4a';
            await addOrUpdateData(
              'cache',
              'song_${id}_${audioQualitySetting.value}_url',
              url,
            );
            sources.add(url);
          }
          songs.add(song);
        }
        final playlist = {'list': songs, 'isCollaborative': !downloaded};

        final firstStarted = platform.started.first;
        await audio.playPlaylistSong(playlist: playlist, songIndex: 0);
        expect(await firstStarted, sources.first);
        expect(audio.mediaItem.value?.extras?['ytid'], songs[0]['ytid']);

        final requested = platform.loading.first;
        final secondStarted = platform.started.first;
        platform.failNextPause = downloaded;
        final gate = platform.loadGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final transition = audio.playPlaylistSong(
          playlist: playlist,
          songIndex: 1,
        );
        expect(await requested, sources.last);
        expect(platform.audibleSource, isNull);
        expect(audio.mediaItem.value?.title, 'Track 1');
        await audio.play();
        expect(platform.audibleSource, isNull);

        gate.complete();
        await transition;
        expect(await secondStarted, sources.last);
        expect(platform.audibleSource, sources.last);
        final item = audio.mediaItem.value!;
        expect(item.extras?['ytid'], songs[1]['ytid']);
        expect(item.title, 'Track 2');
        expect(item.artUri.toString(), songs[1]['highResImage']);
        expect(audio.playbackState.value.queueIndex, 1);
      },
    );
  }
}

class _PlaybackPlatform extends JustAudioPlatform {
  final _loading = StreamController<String>.broadcast();
  final _started = StreamController<String>.broadcast();
  Stream<String> get loading => _loading.stream;
  Stream<String> get started => _started.stream;
  Completer<void>? loadGate;
  Completer<void>? pauseGate;
  bool failNextPause = false;
  String? audibleSource;
  final players = <String, _PlatformPlayer>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      players[request.id] = _PlatformPlayer(request.id, this);

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await players.remove(request.id)?.events.close();
    audibleSource = null;
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

class _PlatformPlayer extends AudioPlayerPlatform {
  _PlatformPlayer(super.id, this.platform);

  final _PlaybackPlatform platform;
  final events = StreamController<PlaybackEventMessage>();
  String? _loadedSource;
  bool _playWhenReady = false;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final playlist =
        request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    final source = (playlist.children.single as UriAudioSourceMessage).uri;
    platform._loading.add(source);
    await platform.loadGate?.future;
    _loadedSource = source;
    publish(ProcessingStateMessage.ready);
    if (_playWhenReady) _startPlayback(source);
    return LoadResponse(duration: const Duration(minutes: 3));
  }

  void publish(ProcessingStateMessage state) {
    const duration = Duration(minutes: 3);
    events.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: duration,
        duration: duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playWhenReady = true;
    final source = _loadedSource;
    if (source != null) _startPlayback(source);
    return PlayResponse();
  }

  void _startPlayback(String source) {
    platform.audibleSource = source;
    platform._started.add(source);
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (platform.failNextPause) {
      platform.failNextPause = false;
      throw PlatformException(code: 'pause-failed');
    }
    await platform.pauseGate?.future;
    _playWhenReady = false;
    platform.audibleSource = null;
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();
}
