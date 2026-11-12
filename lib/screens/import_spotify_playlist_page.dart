import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/artist_service.dart' show ytMusicClient;
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/spotify_playlist_import.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/formatter.dart';
import 'package:vybe/widgets/mini_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// An import row and its original position, used to preserve playlist order.
typedef _ImportRow = ({int index, String title, String artist});

class ImportSpotifyPlaylistPage extends StatefulWidget {
  const ImportSpotifyPlaylistPage({super.key});

  @override
  State<ImportSpotifyPlaylistPage> createState() =>
      _ImportSpotifyPlaylistPageState();
}

class _ImportSpotifyPlaylistPageState extends State<ImportSpotifyPlaylistPage> {
  // Shared across page instances so navigating away and reopening the page
  // can't spawn a second import running concurrently with the first.
  static bool _importRunning = false;

  // Limit concurrency and leave a short pause between batches.
  static const _batchSize = 12;
  static const _batchPause = Duration(milliseconds: 150);

  final _linkController = TextEditingController();
  final _playlistNameController = TextEditingController();
  bool _isImporting = false;
  int _processedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _linkController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  Future<void> _runImport(Future<void> Function() task) async {
    if (_isImporting) return;
    if (_importRunning) {
      showToast(context, context.l10n!.spotifyPlaylistAlreadyImporting);
      return;
    }
    FocusScope.of(context).unfocus();
    _importRunning = true;
    setState(() {
      _isImporting = true;
      _processedCount = 0;
      _totalCount = 0;
    });
    try {
      await task();
    } catch (error, stackTrace) {
      logger.log(
        'Spotify playlist import failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted)
        showToast(context, context.l10n!.spotifyPlaylistImportFailed);
    } finally {
      _importRunning = false;
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importFromLink() => _runImport(() async {
    SpotifyPlaylist playlist;
    try {
      playlist = await loadSpotifyPlaylist(_linkController.text);
    } on FormatException {
      if (mounted) showToast(context, context.l10n!.spotifyLinkInvalid);
      return;
    } catch (_) {
      if (mounted) showToast(context, context.l10n!.spotifyLinkUnavailable);
      return;
    }
    if (!mounted) return;
    if (playlist.tracks.isEmpty) {
      showToast(context, context.l10n!.spotifyLinkNoSongs);
      return;
    }
    if (playlist.mayBeIncomplete) {
      final total = playlist.totalEntries;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n!.spotifyLinkPartialTitle),
          content: Text(
            total == null
                ? context.l10n!.spotifyLinkMayBeIncomplete
                : context.l10n!.spotifyLinkPartialCount(
                    playlist.tracks.length,
                    total,
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n!.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n!.importPlaylist),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    final customName = _playlistNameController.text.trim();
    final name = customName.isNotEmpty
        ? customName
        : playlist.title.isNotEmpty
        ? playlist.title
        : context.l10n!.spotifyPlaylistNameHint;
    await _matchAndSave(
      name,
      playlist.tracks.indexed
          .map(
            (entry) => (
              index: entry.$1,
              title: entry.$2.title,
              artist: entry.$2.artist,
            ),
          )
          .toList(),
    );
  });

  Future<void> _matchAndSave(String playlistName, List<_ImportRow> rows) async {
    setState(() => _totalCount = rows.length);

    // Key results by their original position so retry results remain ordered.
    final foundByIndex = <int, Map>{};
    final firstPass = await _searchBatch(
      rows,
      onProgress: (n) {
        if (mounted) setState(() => _processedCount += n);
      },
    );
    foundByIndex.addAll(firstPass.found);
    var missingRows = firstPass.missing;
    var rateLimited = firstPass.rateLimited;

    // Retry misses once, unless the service is actively rate-limiting us.
    if (!mounted) return;
    if (!rateLimited && missingRows.isNotEmpty) {
      // Include the retry work in the progress total.
      if (mounted) setState(() => _totalCount += missingRows.length);
      final retryPass = await _searchBatch(
        missingRows,
        onProgress: (n) {
          if (mounted) setState(() => _processedCount += n);
        },
      );
      foundByIndex.addAll(retryPass.found);
      missingRows = retryPass.missing;
      rateLimited = retryPass.rateLimited;
    }

    final foundSongs = [
      for (final row in rows)
        if (foundByIndex[row.index] case final song?) song,
    ];

    if (!mounted) return;
    if (foundSongs.isNotEmpty) {
      final (_, playlistId) = createCustomPlaylist(playlistName, null, context);
      addSongsInCustomPlaylist(context, playlistId, foundSongs);
    }

    final resultText = rateLimited
        ? '${context.l10n!.spotifyPlaylistImportFailed}\n${context.l10n!.spotifyPlaylistImportResult(foundSongs.length, rows.length)}'
        : context.l10n!.spotifyPlaylistImportResult(
            foundSongs.length,
            rows.length,
          );
    if (missingRows.isNotEmpty) {
      final missingText = missingRows
          .map((row) => '${row.title} - ${row.artist}')
          .join('\n');
      await Clipboard.setData(ClipboardData(text: missingText));
      if (mounted) {
        showToastWithButton(
          context,
          '$resultText\n${context.l10n!.spotifyPlaylistMissingSongs}',
          context.l10n!.copy,
          () => Clipboard.setData(ClipboardData(text: missingText)),
          duration: const Duration(seconds: 8),
          icon: FluentIcons.warning_24_regular,
        );
      }
    } else {
      showToast(context, resultText);
    }
  }

  /// Resolves [rows] in batches and stops when rate limiting is detected.
  /// Results are keyed by the rows' original positions for retry merging.
  Future<({Map<int, Map> found, List<_ImportRow> missing, bool rateLimited})>
  _searchBatch(
    List<_ImportRow> rows, {
    required void Function(int processedCount) onProgress,
  }) async {
    final found = <int, Map>{};
    final missing = <_ImportRow>[];
    for (var i = 0; i < rows.length; i += _batchSize) {
      if (!mounted) break;
      final batch = rows.skip(i).take(_batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((row) async {
          final (match, wasRateLimited) = await _findSongWithRetry(
            '${row.title} ${row.artist}',
            expectedArtist: row.artist,
            expectedTitle: row.title,
          );
          return (row, match, wasRateLimited);
        }),
      );
      var batchRateLimited = false;
      for (final (row, match, wasRateLimited) in batchResults) {
        if (wasRateLimited) batchRateLimited = true;
        if (match == null) {
          missing.add(row);
        } else {
          found[row.index] = match;
        }
      }
      onProgress(batchResults.length);
      if (batchRateLimited) {
        missing.addAll(rows.skip(i + _batchSize));
        return (found: found, missing: missing, rateLimited: true);
      }
      await Future.delayed(_batchPause);
    }
    return (found: found, missing: missing, rateLimited: false);
  }

  /// Returns the best match for [query], or `null` if none was found.
  /// The second value is `true` when YouTube is actively rate-limiting this
  /// device, so the caller can stop the whole import instead of retrying
  /// every remaining song for minutes on end.
  Future<(Map<String, dynamic>?, bool)> _findSongWithRetry(
    String query, {
    String? expectedArtist,
    String? expectedTitle,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final video = await ytMusicClient.music.searchSong(
          query,
          expectedArtist: expectedArtist,
          expectedTitle: expectedTitle,
        );
        if (video == null) return (null, false);
        return (returnSongLayout(0, video, isCatalogTrack: true), false);
      } on RequestLimitExceededException {
        // A single short retry for a transient hiccup; a second hit means
        // it's a genuine, sustained block.
        if (attempt == maxAttempts - 1) return (null, true);
        await Future.delayed(const Duration(seconds: 2));
      } catch (e, stackTrace) {
        if (attempt == maxAttempts - 1) {
          logger.log(
            'Error searching Spotify import match for "$query"',
            error: e,
            stackTrace: stackTrace,
          );
          return (null, false);
        }
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return (null, false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.importSpotifyPlaylistTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _linkController,
              enabled: !_isImporting,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.l10n!.spotifyLinkLabel,
                hintText: 'https://open.spotify.com/playlist/…',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playlistNameController,
              enabled: !_isImporting,
              decoration: InputDecoration(
                labelText: context.l10n!.playlistName,
                hintText: context.l10n!.spotifyPlaylistNameHint,
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isImporting ? null : _importFromLink,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.link_24_regular),
              label: Text(
                _isImporting
                    ? context.l10n!.spotifyPlaylistImporting
                    : context.l10n!.spotifyImportFromLink,
              ),
            ),
            if (_isImporting && _totalCount > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _processedCount / _totalCount,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n!.spotifyPlaylistProgress(
                  _processedCount,
                  _totalCount,
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: MiniPlayer.playerHeight + 24),
          ],
        ),
      ),
    );
  }
}
