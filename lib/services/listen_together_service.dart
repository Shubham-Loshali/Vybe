import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:vybe/main.dart' show audioHandler, logger;
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/settings_manager.dart' show offlineMode;
import 'package:vybe/utilities/account_name.dart';
import 'package:vybe/utilities/platform_utils.dart';

/// Listen Together: one host shares what they play, guests hear the same
/// song at the same position on their own device.
///
/// No audio is sent between devices. Each device streams the song itself
/// (by its YouTube id); only small state updates go through Firestore:
///
///   listenRooms/{code}                 host state (song, position, playing)
///   listenRooms/{code}/members/{uid}   guest presence
///   listenRooms/{code}/commands/{id}   guest requests (play, pause, seek...)
///
/// Positions are stamped with an estimate of Firestore's server clock, so
/// network delay does not shift guests out of sync.
enum ListenTogetherRole { host, guest }

@immutable
class ListenTogetherSession {
  const ListenTogetherSession({
    required this.code,
    required this.role,
    required this.hostName,
    this.guests = const [],
    this.status,
  });

  final String code;
  final ListenTogetherRole role;
  final String hostName;
  final List<String> guests;
  final String? status;

  bool get isHost => role == ListenTogetherRole.host;

  ListenTogetherSession copyWith({
    String? hostName,
    List<String>? guests,
    String? status,
    bool clearStatus = false,
  }) {
    return ListenTogetherSession(
      code: code,
      role: role,
      hostName: hostName ?? this.hostName,
      guests: guests ?? this.guests,
      status: clearStatus ? null : status ?? this.status,
    );
  }
}

class ListenTogetherService {
  ListenTogetherService._();
  static final ListenTogetherService instance = ListenTogetherService._();

  static const String _roomsCollection = 'listenRooms';
  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int codeLength = 6;

  static const Duration _hostHeartbeat = Duration(seconds: 5);
  static const Duration _guestPresence = Duration(seconds: 15);
  static const Duration _reconcileInterval = Duration(milliseconds: 800);
  static const Duration _hostTimeout = Duration(seconds: 45);
  static const Duration _memberTimeout = Duration(seconds: 60);
  static const Duration _commandMaxAge = Duration(seconds: 30);
  static const Duration _hardSeekThreshold = Duration(milliseconds: 1200);
  static const Duration _driftTolerance = Duration(milliseconds: 50);
  static const Duration _minSeekGap = Duration(milliseconds: 1200);
  static const Duration _loadRetryDelay = Duration(seconds: 5);
  static const Duration _publishDebounce = Duration(milliseconds: 50);
  static const Duration _networkTimeout = Duration(seconds: 10);
  static const Duration _documentTtl = Duration(hours: 12);

  /// The active session, or null.
  final ValueNotifier<ListenTogetherSession?> session =
      ValueNotifier<ListenTogetherSession?>(null);

  /// Why the last session ended, shown once by the UI.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// True while starting or joining.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  final Random _random = Random.secure();

  DocumentReference<Map<String, dynamic>>? _roomRef;
  DocumentReference<Map<String, dynamic>>? _memberRef;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Timer> _timers = [];
  Timer? _publishTimer;

  int _clockOffsetMs = 0;
  int get _serverNowMs => DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  // Host state.
  String? _lastPublishedKey;
  final Set<String> _handledCommandIds = {};

  // Guest state.
  Map<String, dynamic>? _latestRoom;
  bool _reconciling = false;
  bool _reconcileAgain = false;
  String? _failedYtid;
  DateTime _loadRetryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSeekAt;
  bool _measureAfterSeek = false;
  int _seekLeadMs = 300;
  int _presenceTicks = 0;

  bool get isActive => session.value != null;
  bool get _isHost => session.value?.role == ListenTogetherRole.host;
  bool get _isGuest => session.value?.role == ListenTogetherRole.guest;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts a session sharing the current song. Returns an error message,
  /// or null on success.
  Future<String?> startSession() async {
    final error = _precheck();
    if (error != null) return error;
    if (audioHandler.currentSong == null) {
      return 'Play a song first, then start a session.';
    }

    busy.value = true;
    notice.value = null;
    try {
      final user = CloudSyncService.instance.currentUser.value!;
      final rooms = FirebaseFirestore.instance.collection(_roomsCollection);
      final hostName = _displayName();

      DocumentReference<Map<String, dynamic>>? roomRef;
      for (var attempt = 0; attempt < 5 && roomRef == null; attempt++) {
        final candidate = rooms.doc(_randomCode());
        final created = await FirebaseFirestore.instance
            .runTransaction<bool>((tx) async {
              final existing = await tx.get(candidate);
              if (existing.exists) return false;
              tx.set(candidate, {
                'hostUid': user.uid,
                'hostName': hostName,
                'createdAt': FieldValue.serverTimestamp(),
                'ended': false,
                'seq': 0,
                ..._hostStateFields(),
              });
              return true;
            })
            .timeout(_networkTimeout);
        if (created) roomRef = candidate;
      }
      if (roomRef == null) {
        return 'Could not create a session. Please try again.';
      }

      _roomRef = roomRef;
      _memberRef = roomRef.collection('members').doc(user.uid);
      await _memberRef!
          .set({
            'name': hostName,
            'isHost': true,
            'joinedAt': FieldValue.serverTimestamp(),
            'lastSeenMs': _serverNowMs,
            'expireAt': _expireAt(),
          })
          .timeout(_networkTimeout);
      await _syncClock();

      session.value = ListenTogetherSession(
        code: roomRef.id,
        role: ListenTogetherRole.host,
        hostName: hostName,
      );
      await audioHandler.beginSyncSession();
      _startHostListeners();
      await _publishHostState();
      return null;
    } catch (e, stackTrace) {
      logger.log(
        'Listen Together: start failed',
        error: e,
        stackTrace: stackTrace,
      );
      // Close a room that was created before the failure so nobody joins it.
      final createdRoom = _roomRef;
      if (createdRoom != null) {
        unawaited(
          createdRoom.update({'ended': true}).catchError((Object error) {
            logger.log('Listen Together: cleanup failed', error: error);
          }),
        );
      }
      await _leave(reason: null, notifyRemote: true);
      return _friendlyError(e);
    } finally {
      busy.value = false;
    }
  }

  /// Joins the session with [rawCode]. Returns an error message, or null.
  Future<String?> joinSession(String rawCode) async {
    final error = _precheck();
    if (error != null) return error;
    final code = normaliseCode(rawCode);
    if (code.length != codeLength) {
      return 'Enter the $codeLength-character session code.';
    }

    busy.value = true;
    notice.value = null;
    try {
      final user = CloudSyncService.instance.currentUser.value!;
      final roomRef = FirebaseFirestore.instance
          .collection(_roomsCollection)
          .doc(code);
      final snapshot = await roomRef
          .get(const GetOptions(source: Source.server))
          .timeout(_networkTimeout);
      final data = snapshot.data();
      if (!snapshot.exists || data == null || data['ended'] == true) {
        return 'No active session with that code.';
      }
      if (data['hostUid'] == user.uid) {
        return 'This session was started from your account.';
      }

      _roomRef = roomRef;
      _memberRef = roomRef.collection('members').doc(user.uid);
      await _memberRef!
          .set({
            'name': _displayName(),
            'isHost': false,
            'joinedAt': FieldValue.serverTimestamp(),
            'lastSeenMs': _serverNowMs,
            'expireAt': _expireAt(),
          })
          .timeout(_networkTimeout);
      await _syncClock();

      final heartbeat = data['heartbeatAtMs'];
      if (heartbeat is num &&
          _serverNowMs - heartbeat.toInt() > _hostTimeout.inMilliseconds) {
        await _leave(reason: null, notifyRemote: true);
        return 'That session is no longer active.';
      }

      _latestRoom = data;
      session.value = ListenTogetherSession(
        code: code,
        role: ListenTogetherRole.guest,
        hostName: data['hostName']?.toString() ?? 'Host',
      );
      await audioHandler.beginSyncSession(
        followerCommandSink: _sendCommand,
        onFollowerStopped: () => unawaited(leaveSession()),
      );
      _startGuestListeners();
      unawaited(_reconcile());
      return null;
    } catch (e, stackTrace) {
      logger.log('Listen Together: join failed', error: e, stackTrace: stackTrace);
      await _leave(reason: null, notifyRemote: true);
      return _friendlyError(e);
    } finally {
      busy.value = false;
    }
  }

  /// Leaves the session (ends it for everyone when called by the host).
  Future<void> leaveSession() => _leave(reason: null, notifyRemote: true);

  static String normaliseCode(String raw) {
    final input = raw.trim();
    if (input.contains('://')) {
      final uri = Uri.tryParse(input);
      return uri == null ? '' : codeFromLink(uri) ?? '';
    }
    return _normaliseToken(input);
  }

  static String _normaliseToken(String raw) =>
      raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  static String inviteLink(String code) => 'vybe://listen/$code';

  static String? codeFromLink(Uri uri) {
    if (uri.scheme != 'vybe' ||
        uri.host != 'listen' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.pathSegments.length != 1) {
      return null;
    }
    final code = uri.pathSegments.single.toUpperCase();
    return code.length == codeLength && code == _normaliseToken(code)
        ? code
        : null;
  }

  // ---------------------------------------------------------------------------
  // Host
  // ---------------------------------------------------------------------------

  void _startHostListeners() {
    final roomRef = _roomRef!;

    _subscriptions
      ..add(audioHandler.syncEvents.listen((_) => _schedulePublish()))
      ..add(
        audioHandler.playbackStateStream.listen((state) {
          // Publish on play/pause, buffering and song changes only; the
          // position itself is extrapolated by the guests.
          final key = _hostKey(state);
          if (key != _lastPublishedKey) _schedulePublish();
        }),
      )
      ..add(audioHandler.mediaItem.listen((_) => _schedulePublish()))
      ..add(
        roomRef.collection('commands').snapshots().listen(
          _onCommands,
          onError: (Object e) => logger.log('Listen Together commands', error: e),
        ),
      )
      ..add(
        roomRef.collection('members').snapshots().listen(
          _onMembers,
          onError: (Object e) => logger.log('Listen Together members', error: e),
        ),
      )
      ..add(
        roomRef.snapshots().listen(
          _onHostRoomSnapshot,
          onError: (Object e) => logger.log('Listen Together room', error: e),
        ),
      );

    _timers.add(
      Timer.periodic(_hostHeartbeat, (_) => unawaited(_publishHostState())),
    );
  }

  void _onHostRoomSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    // Someone else ended or removed the room (e.g. a TTL cleanup).
    final data = snapshot.data();
    if (!snapshot.metadata.isFromCache &&
        (!snapshot.exists || data?['ended'] == true)) {
      unawaited(_leave(reason: 'The session has ended.', notifyRemote: false));
    }
  }

  String _hostKey(PlaybackState state) {
    final ytid = audioHandler.currentSong?['ytid']?.toString() ?? '';
    final player = audioHandler.audioPlayer;
    final playing =
        player.playing && player.processingState == ProcessingState.ready;
    return '$ytid|$playing|${state.processingState.name}';
  }

  void _schedulePublish() {
    if (!_isHost) return;
    _publishTimer?.cancel();
    _publishTimer = Timer(_publishDebounce, () => unawaited(_publishHostState()));
  }

  Map<String, dynamic> _hostStateFields() {
    final player = audioHandler.audioPlayer;
    final song = audioHandler.currentSong;
    final loaded = audioHandler.isCurrentSongLoaded;
    final now = _serverNowMs;
    return {
      'song': song == null ? null : sanitiseSong(song),
      'positionMs': loaded ? player.position.inMilliseconds : 0,
      // Only "really playing" counts: while the host buffers or loads, the
      // guests must not run ahead.
      'playing':
          loaded &&
          player.playing &&
          player.processingState == ProcessingState.ready,
      'stateAtMs': now,
      'heartbeatAtMs': now,
      'expireAt': _expireAt(),
    };
  }

  Future<void> _publishHostState() async {
    final roomRef = _roomRef;
    if (roomRef == null || !_isHost) return;
    try {
      _lastPublishedKey = _hostKey(audioHandler.playbackState.value);
      await roomRef.update({
        ..._hostStateFields(),
        'seq': FieldValue.increment(1),
      });
    } catch (e, stackTrace) {
      logger.log(
        'Listen Together: publish failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onCommands(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final doc = change.doc;
      if (!_handledCommandIds.add(doc.id)) continue;
      unawaited(
        doc.reference.delete().catchError((Object e) {
          logger.log('Listen Together: command cleanup failed', error: e);
        }),
      );
      final data = doc.data();
      if (data == null) continue;
      final createdAtMs = data['createdAtMs'];
      if (createdAtMs is num &&
          _serverNowMs - createdAtMs.toInt() > _commandMaxAge.inMilliseconds) {
        continue; // Stale request, e.g. sent while the host was offline.
      }
      unawaited(_executeCommand(data));
    }
  }

  Future<void> _executeCommand(Map<String, dynamic> data) async {
    if (!_isHost) return;
    try {
      switch (data['type']) {
        case 'play':
          await audioHandler.play();
        case 'pause':
          await audioHandler.pause();
        case 'seek':
          final positionMs = data['positionMs'];
          if (positionMs is num) {
            await audioHandler.seek(Duration(milliseconds: positionMs.toInt()));
          }
        case 'queue':
        case 'queueNext':
          final queued = data['song'];
          final queuedYtid = queued is Map ? queued['ytid']?.toString() : null;
          if (queued is Map && queuedYtid != null && queuedYtid.isNotEmpty) {
            await audioHandler.addToQueue(
              Map<String, dynamic>.from(queued),
              playNext: data['type'] == 'queueNext',
            );
          }
        case 'next':
          await audioHandler.skipToNext();
        case 'previous':
          await audioHandler.skipToPrevious();
        case 'playSong':
          final song = data['song'];
          final ytid = song is Map ? song['ytid']?.toString() : null;
          if (song is Map && ytid != null && ytid.isNotEmpty) {
            final songMap = Map<String, dynamic>.from(song);
            final hadSong = audioHandler.currentSong != null;
            await audioHandler.addToQueue(songMap, playNext: true);
            // With an empty queue addToQueue already started it.
            if (hadSong && audioHandler.hasNext) {
              await audioHandler.skipToNext();
            }
          }
      }
    } catch (e, stackTrace) {
      logger.log(
        'Listen Together: command failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onMembers(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final current = session.value;
    if (current == null) return;
    final now = _serverNowMs;
    final guests = <String>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isHost'] == true) continue;
      final lastSeen = data['lastSeenMs'];
      if (lastSeen is num &&
          (now - lastSeen.toInt()).abs() > _memberTimeout.inMilliseconds) {
        continue;
      }
      guests.add(data['name']?.toString() ?? 'Guest');
    }
    session.value = current.copyWith(guests: guests);
  }

  // ---------------------------------------------------------------------------
  // Guest
  // ---------------------------------------------------------------------------

  void _startGuestListeners() {
    final roomRef = _roomRef!;
    _subscriptions
      ..add(
        roomRef.snapshots().listen(
          _onRoomSnapshot,
          onError: (Object e) => logger.log('Listen Together room', error: e),
        ),
      )
      ..add(
        roomRef.collection('members').snapshots().listen(
          _onMembers,
          onError: (Object e) => logger.log('Listen Together members', error: e),
        ),
      );

    _timers
      ..add(Timer.periodic(_reconcileInterval, (_) => unawaited(_reconcile())))
      ..add(Timer.periodic(_guestPresence, (_) => unawaited(_updatePresence())));
  }

  Future<void> _updatePresence() async {
    final memberRef = _memberRef;
    if (memberRef == null || !_isGuest) return;
    try {
      await memberRef.update({
        'lastSeenMs': _serverNowMs,
        'expireAt': _expireAt(),
      });
      // Re-measure the clock now and then; phones' clocks drift.
      if (++_presenceTicks % 6 == 0) await _syncClock();
    } catch (e) {
      logger.log('Listen Together: presence update failed', error: e);
    }
  }

  void _onRoomSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!_isGuest) return;
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      if (!snapshot.metadata.isFromCache) {
        unawaited(_leave(reason: 'The session has ended.', notifyRemote: false));
      }
      return;
    }
    if (data['ended'] == true) {
      unawaited(
        _leave(reason: 'The host ended the session.', notifyRemote: false),
      );
      return;
    }
    _latestRoom = data;
    final hostName = data['hostName']?.toString();
    final current = session.value;
    if (current != null && hostName != null && hostName != current.hostName) {
      session.value = current.copyWith(hostName: hostName);
    }
    unawaited(_reconcile());
  }

  /// Brings the guest's player in line with the latest host state. Runs on
  /// every room update and every few seconds; never runs twice at once.
  Future<void> _reconcile() async {
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _reconcileAgain = false;
        await _reconcileOnce();
      } while (_reconcileAgain && _isGuest);
    } catch (e, stackTrace) {
      logger.log(
        'Listen Together: sync failed',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _reconcileOnce() async {
    final room = _latestRoom;
    if (room == null || !_isGuest) return;

    final heartbeat = room['heartbeatAtMs'];
    if (heartbeat is num &&
        _serverNowMs - heartbeat.toInt() > _hostTimeout.inMilliseconds) {
      await _leave(reason: 'Lost connection to the host.', notifyRemote: true);
      return;
    }

    final song = room['song'];
    final ytid = song is Map ? song['ytid']?.toString() : null;
    if (song is! Map || ytid == null || ytid.isEmpty) {
      if (audioHandler.audioPlayer.playing) await audioHandler.syncPause();
      return;
    }

    final localYtid = audioHandler.currentSong?['ytid']?.toString();
    if (localYtid != ytid || !audioHandler.isCurrentSongLoaded) {
      if (_failedYtid == ytid && DateTime.now().isBefore(_loadRetryNotBefore)) {
        return;
      }
      final loaded = await audioHandler.syncLoadSong(
        Map<String, dynamic>.from(song),
      );
      if (!_isGuest) return;
      if (!loaded) {
        _failedYtid = ytid;
        _loadRetryNotBefore = DateTime.now().add(_loadRetryDelay);
        _setStatus("Couldn't load this song. Retrying…");
        return;
      }
      _failedYtid = null;
      _lastSeekAt = null;
      _measureAfterSeek = false;
      _setStatus(null);
    }

    await _alignPosition();
  }

  Future<void> _alignPosition() async {
    final room = _latestRoom;
    if (room == null || !_isGuest) return;
    final song = room['song'];
    final ytid = song is Map ? song['ytid']?.toString() : null;
    // The host moved on while we were loading; the next pass handles it.
    if (ytid == null || ytid != audioHandler.currentSong?['ytid']?.toString()) {
      _reconcileAgain = true;
      return;
    }

    final player = audioHandler.audioPlayer;
    final hostPlaying = room['playing'] == true;
    final positionMs = (room['positionMs'] as num?)?.toInt() ?? 0;
    final stateAtMs = (room['stateAtMs'] as num?)?.toInt() ?? _serverNowMs;
    final expectedMs =
        positionMs + (hostPlaying ? max(0, _serverNowMs - stateAtMs) : 0);
    final durationMs = player.duration?.inMilliseconds;
    final clampedExpectedMs = durationMs != null && expectedMs > durationMs
        ? durationMs
        : expectedMs;

    final state = player.processingState;
    if (state == ProcessingState.loading ||
        state == ProcessingState.buffering) {
      if (!hostPlaying && player.playing) await audioHandler.syncPause();
      return;
    }

    final localPlaying = player.playing;
    final driftMs = player.position.inMilliseconds - clampedExpectedMs;

    // Learn how long a seek takes to start playing, and aim that far ahead.
    if (_measureAfterSeek && hostPlaying && localPlaying) {
      _seekLeadMs = (_seekLeadMs - driftMs ~/ 2).clamp(0, 600);
      _measureAfterSeek = false;
    }

    final now = DateTime.now();
    final canSeek =
        _lastSeekAt == null || now.difference(_lastSeekAt!) >= _minSeekGap;

    // 1. Hard seek when drift is large (> 1200ms) or on fresh song start
    if (driftMs.abs() > _hardSeekThreshold.inMilliseconds && canSeek) {
      final targetMs = clampedExpectedMs + (hostPlaying ? _seekLeadMs : 0);
      _lastSeekAt = now;
      _measureAfterSeek = hostPlaying && localPlaying;
      if (player.speed != 1) {
        unawaited(player.setSpeed(1));
      }
      await audioHandler.syncSeek(Duration(milliseconds: max(0, targetMs).toInt()));
    }
    // 2. Micro-sync: continuous dynamic speed compensation (50ms - 1200ms) with zero audible stutter
    else if (hostPlaying && localPlaying) {
      if (driftMs < -_driftTolerance.inMilliseconds) {
        // Guest is slightly behind: speed up by +4% to smoothly catch up
        if (player.speed != 1.04) {
          unawaited(player.setSpeed(1.04));
        }
      } else if (driftMs > _driftTolerance.inMilliseconds) {
        // Guest is slightly ahead: slow down by -4% to smoothly align
        if (player.speed != 0.96) {
          unawaited(player.setSpeed(0.96));
        }
      } else if (driftMs.abs() <= 30) {
        // Sub-30ms lock: restore exact 1.0x speed
        if (player.speed != 1) {
          unawaited(player.setSpeed(1));
        }
      }
    } else {
      if (player.speed != 1) {
        unawaited(player.setSpeed(1));
      }
    }

    if (hostPlaying && !player.playing) {
      await audioHandler.syncPlay();
    } else if (!hostPlaying && player.playing) {
      await audioHandler.syncPause();
    }
  }

  /// Guest actions go to the host, who applies them for everyone.
  void _sendCommand(String type, {Duration? position, Map? song}) {
    final roomRef = _roomRef;
    final user = CloudSyncService.instance.currentUser.value;
    if (roomRef == null || user == null || !_isGuest) return;
    final command = <String, dynamic>{
      'type': type,
      'byUid': user.uid,
      'byName': _displayName(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': _serverNowMs,
      'expireAt': _expireAt(),
      if (position != null) 'positionMs': position.inMilliseconds,
      if (song != null) 'song': sanitiseSong(song),
    };
    unawaited(
      roomRef.collection('commands').add(command).then<void>(
        (_) {},
        onError: (Object e) {
          logger.log('Listen Together: command send failed', error: e);
          _setStatus("Couldn't reach the host.");
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  String? _precheck() {
    if (!isMobilePlatform) return 'Listen Together is available on Android.';
    if (session.value != null) return 'You are already in a session.';
    if (busy.value) return 'Please wait…';
    if (!CloudSyncService.instance.isFirebaseConfigured) {
      return 'Listen Together is not available right now.';
    }
    if (CloudSyncService.instance.currentUser.value == null) {
      return 'Sign in first to use Listen Together.';
    }
    if (offlineMode.value) {
      return 'Turn off offline mode to use Listen Together.';
    }
    return null;
  }

  /// Estimates the offset between this phone's clock and Firestore's.
  /// Takes the sample with the shortest round trip (least uncertainty).
  Future<void> _syncClock() async {
    final memberRef = _memberRef;
    if (memberRef == null) return;
    int? bestRoundTrip;
    int? bestOffset;
    for (var i = 0; i < 3; i++) {
      try {
        final sentAt = DateTime.now().millisecondsSinceEpoch;
        await memberRef
            .set({
              'clockProbe': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_networkTimeout);
        final ackedAt = DateTime.now().millisecondsSinceEpoch;
        final snapshot = await memberRef
            .get(const GetOptions(source: Source.server))
            .timeout(_networkTimeout);
        final serverTime = snapshot.data()?['clockProbe'];
        if (serverTime is! Timestamp) continue;
        final roundTrip = ackedAt - sentAt;
        final offset =
            serverTime.millisecondsSinceEpoch - (sentAt + roundTrip ~/ 2);
        if (bestRoundTrip == null || roundTrip < bestRoundTrip) {
          bestRoundTrip = roundTrip;
          bestOffset = offset;
        }
      } catch (e) {
        logger.log('Listen Together: clock sample failed', error: e);
      }
    }
    if (bestOffset != null) _clockOffsetMs = bestOffset;
  }

  Future<void> _leave({
    required String? reason,
    required bool notifyRemote,
  }) async {
    final roomRef = _roomRef;
    final memberRef = _memberRef;
    final wasHost = _isHost;

    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _publishTimer?.cancel();
    _publishTimer = null;
    _roomRef = null;
    _memberRef = null;
    _latestRoom = null;
    _lastPublishedKey = null;
    _handledCommandIds.clear();
    _failedYtid = null;
    _lastSeekAt = null;
    _measureAfterSeek = false;
    _reconcileAgain = false;

    final hadSession = session.value != null;
    session.value = null;
    if (reason != null) notice.value = reason;
    try {
      if (audioHandler.audioPlayer.speed != 1) {
        unawaited(audioHandler.audioPlayer.setSpeed(1));
      }
    } catch (_) {}
    audioHandler.endSyncSession();

    // Remote cleanup never blocks leaving locally.
    if (memberRef != null) {
      unawaited(
        memberRef.delete().catchError((Object e) {
          logger.log('Listen Together: member cleanup failed', error: e);
        }),
      );
    }
    if (notifyRemote && wasHost && roomRef != null && hadSession) {
      try {
        await roomRef
            .update({'ended': true, 'heartbeatAtMs': _serverNowMs})
            .timeout(_networkTimeout);
      } catch (e) {
        logger.log('Listen Together: ending session failed', error: e);
      }
    }
  }

  void _setStatus(String? status) {
    final current = session.value;
    if (current == null || current.status == status) return;
    session.value = status == null
        ? current.copyWith(clearStatus: true)
        : current.copyWith(status: status);
  }

  String _randomCode() => List.generate(
    codeLength,
    (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
  ).join();

  Timestamp _expireAt() => Timestamp.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch + _documentTtl.inMilliseconds,
  );

  String _displayName() =>
      accountDisplayName(CloudSyncService.instance.currentUser.value) ??
      'Vybe listener';

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The connection timed out. Check your internet and try again.';
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Listen Together is not set up on the server yet.';
    }
    return 'Something went wrong. Please try again.';
  }

  static const List<String> _songKeys = [
    'id',
    'ytid',
    'title',
    'artist',
    'album',
    'artistId',
    'videoAuthor',
    'highResImage',
    'lowResImage',
    'image',
    'duration',
    'isLive',
  ];

  /// Only plain, shareable fields: never local file paths or queue flags.
  static Map<String, dynamic> sanitiseSong(Map song) {
    final result = <String, dynamic>{};
    for (final key in _songKeys) {
      final value = song[key];
      if (value is String || value is num || value is bool) {
        result[key] = value;
      } else if (value is Duration) {
        result[key] = value.inSeconds;
      }
    }
    final ytid = result['ytid'];
    if (ytid != null) result['id'] = ytid;
    return result;
  }
}
