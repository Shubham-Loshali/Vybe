import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/utilities/playlist_utils.dart';

class CollaborativePlaylistService {
  CollaborativePlaylistService._internal();
  static final CollaborativePlaylistService instance =
      CollaborativePlaylistService._internal();

  static const String _collectionName = 'collaborativePlaylists';
  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int codeLength = 6;

  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _subscriptions = {};
  final Random _random = Random.secure();
  bool _initialised = false;

  /// Initializes listeners for all active collaborative playlists in local storage.
  void initialise() {
    if (_initialised) return;
    _initialised = true;

    _syncAllActiveCollabPlaylists();
    userCustomPlaylists.addListener(_onLocalPlaylistsChanged);
  }

  void _onLocalPlaylistsChanged() {
    _syncAllActiveCollabPlaylists();
  }

  void _syncAllActiveCollabPlaylists() {
    final activeCollabCodes = <String>{};
    for (final p in userCustomPlaylists.value) {
      if (p['isCollaborative'] == true) {
        final code = (p['collabId'] ?? p['inviteCode'])?.toString();
        if (code != null && code.isNotEmpty) {
          activeCollabCodes.add(code);
          _listenToCollabPlaylist(code);
        }
      }
    }

    // Cancel subscriptions for playlists no longer in user's library
    final existingCodes = _subscriptions.keys.toList();
    for (final existing in existingCodes) {
      if (!activeCollabCodes.contains(existing)) {
        _subscriptions[existing]?.cancel();
        _subscriptions.remove(existing);
      }
    }
  }

  /// Generates a random 6-character room/collab code.
  String _randomCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < codeLength; i++) {
      buffer.write(_codeAlphabet[_random.nextInt(_codeAlphabet.length)]);
    }
    return buffer.toString();
  }

  /// Normalizes a code or deep link string into a clean uppercase code.
  static String normaliseCode(String raw) {
    var cleaned = raw.trim();
    if (cleaned.contains('://')) {
      final link = Uri.tryParse(cleaned);
      if (link == null || link.userInfo.isNotEmpty) return '';
      final segments = link.pathSegments;
      if (link.scheme == 'vybe' &&
          link.host == 'collab' &&
          segments.length == 1) {
        cleaned = segments.single;
      } else if (link.scheme == 'https' &&
          link.host == 'vybe.app' &&
          segments.length == 2 &&
          segments.first == 'collab') {
        cleaned = segments.last;
      } else {
        return '';
      }
    }
    return cleaned.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  }

  /// Creates a shareable deep link from a code.
  static String inviteLink(String code) => 'vybe://collab/${normaliseCode(code)}';

  /// Creates a new collaborative playlist.
  Future<({bool success, String message, String? playlistId, String? inviteCode})>
      createCollaborativePlaylist(
    String title, {
    String? image,
    BuildContext? context,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'Collaborative Playlist' : title.trim();
    final inviteCode = _randomCode();
    final newPlaylistId = PlaylistUtils.generateCustomPlaylistId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final uid = _currentUid();
    final userName = _displayName();

    final collaboratorEntry = {
      'uid': uid,
      'name': userName,
      'isOwner': true,
      'joinedAt': now,
    };

    final playlistData = <String, dynamic>{
      'ytid': newPlaylistId,
      'id': newPlaylistId,
      'collabId': inviteCode,
      'inviteCode': inviteCode,
      'title': cleanTitle,
      'source': 'user-created',
      'isCollaborative': true,
      'ownerUid': uid,
      'ownerName': userName,
      if (image != null && image.isNotEmpty) 'image': image,
      'list': <dynamic>[],
      'collaborators': [collaboratorEntry],
      'createdAt': now,
      'updatedAt': now,
    };

    // Save locally
    userCustomPlaylists.value = [...userCustomPlaylists.value, playlistData];
    await _persistLocalPlaylists();

    // Push to Firestore in background without blocking dialog
    try {
      unawaited(
        FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(inviteCode)
            .set({
              'id': inviteCode,
              'title': cleanTitle,
              'ownerUid': uid,
              'ownerName': userName,
              'image': image,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'collaborators': [collaboratorEntry],
              'songs': <dynamic>[],
            })
            .then((_) => _listenToCollabPlaylist(inviteCode))
            .catchError((e, stackTrace) {
              logger.log(
                'Firestore create collaborative playlist error (saved locally)',
                error: e,
                stackTrace: stackTrace,
              );
            }),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Firestore create collaborative playlist error (saved locally)',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return (
      success: true,
      message: 'Collaborative playlist created!',
      playlistId: newPlaylistId,
      inviteCode: inviteCode,
    );
  }

  /// Upgrades an existing custom playlist to be collaborative.
  Future<({bool success, String message, String? inviteCode})>
      makePlaylistCollaborative(String playlistId) async {
    final index = userCustomPlaylists.value.indexWhere(
      (p) => (p['ytid'] ?? p['id'])?.toString() == playlistId,
    );
    if (index == -1) {
      return (success: false, message: 'Playlist not found', inviteCode: null);
    }

    final existing = Map<String, dynamic>.from(userCustomPlaylists.value[index]);
    if (existing['isCollaborative'] == true && existing['inviteCode'] != null) {
      return (
        success: true,
        message: 'Already collaborative',
        inviteCode: existing['inviteCode']?.toString(),
      );
    }

    final inviteCode = _randomCode();
    final uid = _currentUid();
    final userName = _displayName();
    final now = DateTime.now().millisecondsSinceEpoch;

    final collaboratorEntry = {
      'uid': uid,
      'name': userName,
      'isOwner': true,
      'joinedAt': now,
    };

    // Stamp existing songs with owner attribution
    final stampedSongs = <Map<String, dynamic>>[];
    for (final song in (existing['list'] as List? ?? [])) {
      if (song is Map) {
        final s = Map<String, dynamic>.from(song);
        s['addedByUid'] ??= uid;
        s['addedByName'] ??= userName;
        s['addedAt'] ??= now;
        stampedSongs.add(s);
      }
    }

    existing['isCollaborative'] = true;
    existing['collabId'] = inviteCode;
    existing['inviteCode'] = inviteCode;
    existing['ownerUid'] = uid;
    existing['ownerName'] = userName;
    existing['collaborators'] = [collaboratorEntry];
    existing['list'] = stampedSongs;
    existing['updatedAt'] = now;

    final updatedList = List<Map>.from(userCustomPlaylists.value);
    updatedList[index] = existing;
    userCustomPlaylists.value = updatedList;
    await _persistLocalPlaylists();

    try {
      final docRef = FirebaseFirestore.instance.collection(_collectionName).doc(inviteCode);
      await docRef.set({
        'id': inviteCode,
        'title': existing['title'] ?? 'Collaborative Playlist',
        'ownerUid': uid,
        'ownerName': userName,
        'image': existing['image'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'collaborators': [collaboratorEntry],
        'songs': stampedSongs,
      }).timeout(const Duration(seconds: 10));

      _listenToCollabPlaylist(inviteCode);
    } catch (e, stackTrace) {
      logger.log('Firestore make collaborative error', error: e, stackTrace: stackTrace);
    }

    return (
      success: true,
      message: 'Playlist is now collaborative!',
      inviteCode: inviteCode,
    );
  }

  /// Joins a collaborative playlist with a code or link.
  Future<({bool success, String message, Map<String, dynamic>? playlist})>
      joinCollaborativePlaylist(String codeOrLink) async {
    final code = normaliseCode(codeOrLink);
    if (code.length != codeLength) {
      return (
        success: false,
        message: 'Invalid invite code. Must be 6 characters.',
        playlist: null,
      );
    }

    // Check if user is already a member locally
    final existingLocalIndex = userCustomPlaylists.value.indexWhere(
      (p) => (p['collabId'] ?? p['inviteCode'])?.toString() == code,
    );
    if (existingLocalIndex != -1) {
      final local = Map<String, dynamic>.from(userCustomPlaylists.value[existingLocalIndex]);
      _listenToCollabPlaylist(code);
      return (
        success: true,
        message: 'You are already in this playlist!',
        playlist: local,
      );
    }

    try {
      final docRef = FirebaseFirestore.instance.collection(_collectionName).doc(code);
      final snapshot = await docRef.get().timeout(const Duration(seconds: 10));

      if (!snapshot.exists || snapshot.data() == null) {
        return (
          success: false,
          message: 'No collaborative playlist found with code $code.',
          playlist: null,
        );
      }

      final data = snapshot.data()!;
      final uid = _currentUid();
      final userName = _displayName();
      final now = DateTime.now().millisecondsSinceEpoch;

      final collaborators = List<Map<String, dynamic>>.from(
        (data['collaborators'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from),
      );

      // Add user to collaborators if not already present
      if (!collaborators.any((c) => c['uid'] == uid)) {
        final newMember = {
          'uid': uid,
          'name': userName,
          'isOwner': false,
          'joinedAt': now,
        };
        await docRef.update({
          'collaborators': FieldValue.arrayUnion([newMember]),
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10));
        collaborators.add(newMember);
      }

      final rawSongs = data['songs'] as List? ?? [];
      final songs = List<Map<String, dynamic>>.from(
        rawSongs.whereType<Map>().map((s) {
          final m = Map<String, dynamic>.from(s);
          m['ytid'] ??= m['id'];
          return m;
        }),
      );

      final playlistMap = <String, dynamic>{
        'ytid': PlaylistUtils.generateCustomPlaylistId(),
        'id': code,
        'collabId': code,
        'inviteCode': code,
        'title': data['title']?.toString() ?? 'Collaborative Playlist',
        'source': 'user-created',
        'isCollaborative': true,
        'ownerUid': data['ownerUid']?.toString() ?? '',
        'ownerName': data['ownerName']?.toString() ?? 'Owner',
        'image': data['image']?.toString(),
        'list': songs,
        'collaborators': collaborators,
        'createdAt': (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
            : now,
        'updatedAt': now,
      };

      userCustomPlaylists.value = [...userCustomPlaylists.value, playlistMap];
      await _persistLocalPlaylists();

      _listenToCollabPlaylist(code);

      return (
        success: true,
        message: 'Joined playlist "${playlistMap['title']}"!',
        playlist: playlistMap,
      );
    } catch (e, stackTrace) {
      logger.log('joinCollaborativePlaylist error', error: e, stackTrace: stackTrace);
      return (
        success: false,
        message: 'Could not connect to collaborative server. Check connection.',
        playlist: null,
      );
    }
  }

  /// Adds a song to a collaborative playlist and syncs it in real time.
  Future<bool> addSong(String collabCodeOrId, Map song) async {
    final uid = _currentUid();
    final userName = _displayName();
    final now = DateTime.now().millisecondsSinceEpoch;

    final stampedSong = Map<String, dynamic>.from(song);
    stampedSong['addedByUid'] = uid;
    stampedSong['addedByName'] = userName;
    stampedSong['addedAt'] = now;

    // 1. Immediately update local state
    final index = userCustomPlaylists.value.indexWhere(
      (p) =>
          (p['collabId'] ?? p['inviteCode'])?.toString() ==
              normaliseCode(collabCodeOrId) ||
          (p['ytid'] ?? p['id'])?.toString() == collabCodeOrId,
    );
    String? code;
    if (index != -1) {
      final playlist = Map<String, dynamic>.from(userCustomPlaylists.value[index]);
      code = (playlist['collabId'] ?? playlist['inviteCode'])?.toString();
      final list = List<dynamic>.from(playlist['list'] as List? ?? []);

      final targetYtid = (song['ytid'] ?? song['id'])?.toString();
      if (list.any((s) =>
          s is Map &&
          targetYtid != null &&
          (s['ytid'] ?? s['id'])?.toString() == targetYtid)) {
        return false; // Already present
      }

      list.add(stampedSong);
      playlist['list'] = list;
      playlist['updatedAt'] = now;

      final updated = List<Map>.from(userCustomPlaylists.value);
      updated[index] = playlist;
      userCustomPlaylists.value = updated;
      unawaited(_persistLocalPlaylists());
    }

    code ??= normaliseCode(collabCodeOrId);

    // 2. Sync to Firestore in real time
    try {
      final docRef = FirebaseFirestore.instance.collection(_collectionName).doc(code);
      await docRef.update({
        'songs': FieldValue.arrayUnion([stampedSong]),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      logger.log('Collaborative addSong remote sync failed', error: e);
      return true; // Still preserved locally
    }
  }

  /// Removes a song from a collaborative playlist.
  Future<bool> removeSong(String collabCodeOrId, String songYtid) async {
    final index = userCustomPlaylists.value.indexWhere(
      (p) =>
          (p['collabId'] ?? p['inviteCode'])?.toString() ==
              normaliseCode(collabCodeOrId) ||
          (p['ytid'] ?? p['id'])?.toString() == collabCodeOrId,
    );
    String? code;
    Map<dynamic, dynamic>? songToRemove;

    if (index != -1) {
      final playlist = Map<String, dynamic>.from(userCustomPlaylists.value[index]);
      code = (playlist['collabId'] ?? playlist['inviteCode'])?.toString();
      final list = List<dynamic>.from(playlist['list'] as List? ?? []);

      final songIndex = list.indexWhere(
        (s) =>
            s is Map &&
            (s['ytid'] ?? s['id'])?.toString() == songYtid,
      );
      if (songIndex != -1) {
        songToRemove = list[songIndex] as Map;
        list.removeAt(songIndex);
        playlist['list'] = list;
        playlist['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

        final updated = List<Map>.from(userCustomPlaylists.value);
        updated[index] = playlist;
        userCustomPlaylists.value = updated;
        unawaited(_persistLocalPlaylists());
      }
    }

    code ??= normaliseCode(collabCodeOrId);
    if (songToRemove == null) return false;

    try {
      final docRef = FirebaseFirestore.instance.collection(_collectionName).doc(code);
      final docSnap = await docRef.get().timeout(const Duration(seconds: 4));
      final remoteSongs = docSnap.data()?['songs'] as List? ?? const [];
      final matchingSongs = remoteSongs.where((song) {
        return song is Map &&
            (song['ytid'] ?? song['id'])?.toString() == songYtid;
      }).toList();
      await docRef.update({
        'songs': FieldValue.arrayRemove(
          matchingSongs.isEmpty ? [songToRemove] : matchingSongs,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 4));
      return true;
    } catch (e) {
      logger.log('Collaborative removeSong remote sync failed', error: e);
      return true;
    }
  }

  /// Listens for real-time changes to the collaborative playlist from Firestore.
  void _listenToCollabPlaylist(String code) {
    if (_subscriptions.containsKey(code)) return;

    try {
      final docRef = FirebaseFirestore.instance.collection(_collectionName).doc(code);
      // ignore: cancel_subscriptions
      final sub = docRef.snapshots().listen(
        (snapshot) {
          if (!snapshot.exists || snapshot.data() == null) return;
          final data = snapshot.data()!;

          final index = userCustomPlaylists.value.indexWhere(
            (p) => (p['collabId'] ?? p['inviteCode'])?.toString() == code,
          );
          if (index == -1) return;

          final current = Map<String, dynamic>.from(userCustomPlaylists.value[index]);
          final rawSongs = data['songs'] as List? ?? [];
          final songs = List<Map<String, dynamic>>.from(
            rawSongs.whereType<Map>().map((s) {
              final m = Map<String, dynamic>.from(s);
              m['ytid'] ??= m['id'];
              return m;
            }),
          );
          final rawCollaborators = data['collaborators'] as List? ?? [];
          final collaborators = List<Map<String, dynamic>>.from(
            rawCollaborators.whereType<Map>().map(Map<String, dynamic>.from),
          );

          current['title'] = data['title']?.toString() ?? current['title'];
          current['list'] = songs;
          current['collaborators'] = collaborators;
          current['image'] = data['image']?.toString() ?? current['image'];

          final updated = List<Map>.from(userCustomPlaylists.value);
          updated[index] = current;
          userCustomPlaylists.value = updated;
          unawaited(_persistLocalPlaylists());
        },
        onError: (Object e) {
          logger.log('Collaborative listener error on $code', error: e);
        },
      );

      _subscriptions[code] = sub;
    } catch (e) {
      logger.log('Failed to start collaborative listener on $code', error: e);
    }
  }

  String _displayName() {
    final user = CloudSyncService.instance.currentUser.value;
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Music Lover';
  }

  String _currentUid() {
    final user = CloudSyncService.instance.currentUser.value;
    return user?.uid ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _persistLocalPlaylists() async {
    try {
      final userBox = Hive.box('user');
      await userBox.put('customPlaylists', userCustomPlaylists.value);
    } catch (e, stackTrace) {
      logger.log('Failed to persist collaborative playlist to user box',
          error: e, stackTrace: stackTrace);
    }
  }

  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    userCustomPlaylists.removeListener(_onLocalPlaylistsChanged);
  }
}
