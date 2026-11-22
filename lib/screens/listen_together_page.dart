import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/utilities/account_name.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';

/// Opens the Listen Together (Spotify Jam) screen on top of everything else.
Future<void> openListenTogetherPage(
  BuildContext context, {
  String? initialCode,
  bool joinOnly = false,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ListenTogetherPage(initialCode: initialCode, joinOnly: joinOnly),
    ),
  );
}

class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({
    super.key,
    this.initialCode,
    this.joinOnly = false,
  });

  final String? initialCode;
  final bool joinOnly;

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final _service = ListenTogetherService.instance;
  late final TextEditingController _codeController = TextEditingController(
    text: ListenTogetherService.normaliseCode(widget.initialCode ?? ''),
  );
  bool _guestsCanControl = true;

  @override
  void initState() {
    super.initState();
    _service.notice.addListener(_showNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice());
  }

  @override
  void dispose() {
    _service.notice.removeListener(_showNotice);
    _codeController.dispose();
    super.dispose();
  }

  void _showNotice() {
    final message = _service.notice.value;
    if (message == null || !mounted) return;
    _service.notice.value = null;
    showToast(context, message);
  }

  Future<void> _start() async {
    final error = await _service.startSession();
    if (error != null && mounted) showToast(context, error);
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    final error = await _service.joinSession(_codeController.text);
    if (error != null && mounted) showToast(context, error);
  }

  Future<void> _leave(bool isHost) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: Text(
          isHost ? 'End Jam?' : 'Leave Jam?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          isHost
              ? 'Everyone in the Jam will stop listening with you.'
              : 'You will stop listening along. Your music keeps playing.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              isHost ? 'End Jam' : 'Leave',
              style: const TextStyle(
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _service.leaveSession();
  }

  Future<void> _share(String code) async {
    final link = ListenTogetherService.inviteLink(code);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Listen with me in my Jam on Vybe! Tap $link or enter code $code to join.',
          subject: 'Join my Jam on Vybe',
        ),
      );
    } catch (_) {
      if (mounted) showToast(context, 'Unable to share');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _service.busy,
    builder: (context, busy, _) => PopScope(
      canPop: !widget.joinOnly || !busy,
      child: _buildPage(busy),
    ),
  );

  Widget _buildPage(bool busy) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular, color: Colors.white),
          onPressed: widget.joinOnly && busy
              ? null
              : () => Navigator.pop(context),
        ),
        title: const Text(
          'Jam',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Figtree',
          ),
        ),
      ),
      body: ValueListenableBuilder<User?>(
        valueListenable: CloudSyncService.instance.currentUser,
        builder: (context, user, _) {
          return ValueListenableBuilder<ListenTogetherSession?>(
            valueListenable: _service.session,
            builder: (context, session, _) {
              final Widget content;
              if (session != null) {
                content = _buildSession(context, session);
              } else if (user == null) {
                content = _buildSignIn(context);
              } else {
                content = widget.joinOnly
                    ? _buildJoinForm(busy)
                    : _buildStartOrJoin(busy, accountDisplayName(user));
              }
              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [content, const MiniPlayerBottomSpace()],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSignIn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFF5D1248),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              FluentIcons.people_community_24_regular,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Listen together in a Jam',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Start a Jam and invite friends to listen at the same time and control the queue together.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          onPressed: () async {
            await CloudSyncService.instance.signInWithGoogle();
            final message = CloudSyncService.instance.syncMessage.value;
            if (mounted &&
                CloudSyncService.instance.currentUser.value == null &&
                message != null) {
              showToast(this.context, message);
            }
          },
          icon: const Icon(FluentIcons.person_24_filled, size: 20),
          label: const Text(
            'Sign in with Google',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildStartOrJoin(bool busy, String? displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Spotify Jam Hero Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5D1248), Color(0xFF2C0A22)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFB4D6),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initial(displayName),
                      style: const TextStyle(
                        color: Color(0xFF4C0838),
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      FluentIcons.add_20_regular,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Start your own Jam',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Friends listen in sync and can add songs to the shared queue in real time.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: busy ? null : _start,
                  child: const Text(
                    'Start a Jam',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _buildJoinForm(busy),
        if (busy) ...[
          const SizedBox(height: 24),
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Everyone streams the song on their own phone in real time.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildJoinForm(bool busy) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF242424),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Join a Jam',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Enter the 6-character code or paste the Jam invite link.',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _codeController,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            letterSpacing: 1,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: 'Code or invite link',
            hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1),
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onSubmitted: busy ? null : (_) => _join(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: busy ? null : _join,
          icon: const Icon(FluentIcons.person_arrow_right_24_regular, size: 18),
          label: Text(
            widget.joinOnly && busy ? 'Joining…' : 'Join Jam',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  String _initial(String? name) {
    final displayName = name?.trim() ?? '';
    return displayName.isEmpty
        ? '?'
        : displayName.characters.first.toUpperCase();
  }

  Widget _buildSession(BuildContext context, ListenTogetherSession session) {
    final guests = session.guests;
    final hostInitial = _initial(session.hostName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Active Jam Banner Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5D1248), Color(0xFF2C0A22)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Avatar Stack
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFB4D6),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      hostInitial,
                      style: const TextStyle(
                        color: Color(0xFF4C0838),
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  for (final guest in guests.take(3)) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFF9D4EDD),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initial(guest),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${session.hostName}’s Jam',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                session.isHost
                    ? (guests.isEmpty
                        ? 'No one else is here yet'
                        : '${guests.length} friend${guests.length == 1 ? '' : 's'} listening with you')
                    : 'Listening along with ${session.hostName}',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Spotify Green Primary Button: Share link
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () => _share(session.code),
                  icon: const Icon(FluentIcons.share_24_filled, size: 20),
                  label: const Text(
                    'Share link',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Code Box (Spotify Style)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                FluentIcons.qr_code_24_regular,
                color: Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite code',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      session.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1DB954),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: session.code));
                  if (mounted) showToast(this.context, 'Code copied: ${session.code}');
                },
                icon: const Icon(FluentIcons.copy_20_regular, size: 18),
                label: const Text(
                  'Copy',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        if (session.status != null) ...[
          const SizedBox(height: 12),
          Text(
            session.status!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
          ),
        ],

        const SizedBox(height: 20),

        // Spotify Jam Control Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                FluentIcons.music_note_2_24_regular,
                color: Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Let guests control playback',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Everyone can play, pause, seek, and add songs',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _guestsCanControl,
                activeTrackColor: const Color(0xFF1DB954),
                onChanged: (val) {
                  setState(() {
                    _guestsCanControl = val;
                  });
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Participants List: "In this Jam"
        const Text(
          'In this Jam',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),

        // Host Tile
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFB4D6),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  hostInitial,
                  style: const TextStyle(
                    color: Color(0xFF4C0838),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.hostName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Host',
                  style: TextStyle(
                    color: Color(0xFF1DB954),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Guest Tiles
        for (final guest in guests)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF9D4EDD),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial(guest),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    guest,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Guest',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // End / Leave Jam Button (Spotify Outlined Pill)
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF5252),
            side: const BorderSide(color: Color(0xFF442222)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          onPressed: () => _leave(session.isHost),
          child: Text(
            session.isHost ? 'End Jam' : 'Leave Jam',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ),
      ],
    );
  }
}
