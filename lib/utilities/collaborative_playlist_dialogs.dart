import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/utilities/flutter_toast.dart';

/// Shows a dialog to join a collaborative playlist using an invite code or link.
Future<void> showJoinCollaborativePlaylistDialog(BuildContext context) async {
  final result = await showDialog<({String playlistId, String message})>(
    context: context,
    builder: (_) => const _JoinCollaborativePlaylistDialog(),
  );
  if (result == null || !context.mounted) return;
  showToast(context, result.message);
  unawaited(context.push(NavigationManager.playlistPath(result.playlistId)));
}

class _JoinCollaborativePlaylistDialog extends StatefulWidget {
  const _JoinCollaborativePlaylistDialog();

  @override
  State<_JoinCollaborativePlaylistDialog> createState() =>
      _JoinCollaborativePlaylistDialogState();
}

class _JoinCollaborativePlaylistDialogState
    extends State<_JoinCollaborativePlaylistDialog> {
  final _controller = TextEditingController();
  bool _isJoining = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_isJoining) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter a 6-character code or link.');
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });
    final result = await CollaborativePlaylistService.instance
        .joinCollaborativePlaylist(text);
    if (!mounted) return;

    final playlist = result.playlist;
    final playlistId = (playlist?['ytid'] ?? playlist?['id'])?.toString();
    if (result.success && playlistId != null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context)
            .pop((playlistId: playlistId, message: result.message));
      }
      return;
    }
    setState(() {
      _isJoining = false;
      _error = result.success ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: const Color(0xFF242424),
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1DB954).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          FluentIcons.people_team_24_filled,
          color: Color(0xFF1DB954),
          size: 28,
        ),
      ),
      title: const Text(
        'Join Collaborative Playlist',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the 6-character invite code or paste the invite link shared by your friend.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            readOnly: _isJoining,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              color: Colors.white,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'e.g. ABC123',
              errorText: _error,
              errorMaxLines: 3,
              hintStyle: const TextStyle(
                color: Colors.white38,
                letterSpacing: 1,
              ),
              filled: true,
              fillColor: const Color(0xFF333333),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(
                  FluentIcons.clipboard_paste_20_regular,
                  color: Colors.white70,
                ),
                tooltip: 'Paste from clipboard',
                onPressed: _isJoining
                    ? null
                    : () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        final text = data?.text;
                        if (!mounted || _isJoining || text == null) return;
                        _controller.text =
                            CollaborativePlaylistService.normaliseCode(text);
                        if (_error != null) setState(() => _error = null);
                      },
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        FilledButton(
          onPressed: _isJoining ? null : _join,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
            foregroundColor: Colors.black,
          ),
          child: _isJoining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text(
                  'Join Playlist',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}

/// Shows a dialog displaying collaborative playlist details, invite code, share link, and members.
void showCollaborativePlaylistShareDialog(BuildContext context, Map playlist) {
  final playlistMap = Map<String, dynamic>.from(playlist);
  var code =
      (playlistMap['collabId'] ?? playlistMap['inviteCode'])
          ?.toString()
          .trim() ??
      '';
  if (code.isEmpty) {
    final digits = DateTime.now().millisecondsSinceEpoch.toString();
    code = 'VY${digits.substring(digits.length - 4)}'.toUpperCase();
    try {
      playlist['collabId'] = code;
      playlist['inviteCode'] = code;
    } catch (_) {}
    playlistMap['collabId'] = code;
    playlistMap['inviteCode'] = code;
  }
  final link = CollaborativePlaylistService.inviteLink(code);
  final title = playlistMap['title']?.toString() ?? 'Playlist';
  var collaborators = <Map<String, dynamic>>[];
  try {
    final rawList = playlistMap['collaborators'];
    if (rawList is List) {
      collaborators = List<Map<String, dynamic>>.from(
        rawList.whereType<Map>().map(Map<String, dynamic>.from),
      );
    }
  } catch (_) {}

  try {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF242424),
          title: Row(
            children: [
              const Icon(
                FluentIcons.people_team_24_filled,
                color: Color(0xFF1DB954),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Anyone with this code or link can add and manage songs in real time.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'INVITE CODE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        code,
                        style: const TextStyle(
                          color: Color(0xFF1DB954),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          showToast(dialogContext, 'Code copied to clipboard!');
                        },
                        icon: const Icon(
                          FluentIcons.copy_20_regular,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Copy Code',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: link));
                          showToast(dialogContext, 'Link copied to clipboard!');
                        },
                        icon: const Icon(
                          FluentIcons.link_20_regular,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Copy Link',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    unawaited(
                      SharePlus.instance.share(
                        ShareParams(
                          text:
                              'Collaborate on my playlist "$title" on Vybe!\nCode: $code\nLink: $link',
                          subject: 'Join my playlist: $title',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(FluentIcons.share_20_filled, size: 18),
                  label: const Text(
                    'Share Invite Link',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.black,
                  ),
                ),
                if (collaborators.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'COLLABORATORS (${collaborators.length})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in collaborators)
                    Builder(
                      builder: (context) {
                        final rawName = c['name']?.toString().trim();
                        final displayName =
                            (rawName != null && rawName.isNotEmpty)
                            ? rawName
                            : 'Collaborator';
                        final initial = (rawName != null && rawName.isNotEmpty)
                            ? rawName[0].toUpperCase()
                            : 'U';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: const Color(0xFF333333),
                                child: Text(
                                  initial,
                                  style: const TextStyle(
                                    color: Color(0xFF1DB954),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (c['isOwner'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1DB954)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'OWNER',
                                    style: TextStyle(
                                      color: Color(0xFF1DB954),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Done',
                style: TextStyle(color: Color(0xFF1DB954)),
              ),
            ),
          ],
        );
      },
    );
  } catch (e, stackTrace) {
    debugPrint('Error showing collaborative playlist dialog: $e\n$stackTrace');
  }
}
