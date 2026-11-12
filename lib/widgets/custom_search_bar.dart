import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

class CustomSearchBar extends StatefulWidget {
  const CustomSearchBar({
    super.key,
    required this.onSubmitted,
    required this.controller,
    required this.focusNode,
    required this.labelText,
    this.onChanged,
    this.loadingProgressNotifier,
    this.prominent = false,
  });
  final Function(String) onSubmitted;
  final ValueNotifier<bool>? loadingProgressNotifier;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final Function(String)? onChanged;

  /// White field with dark text, as on Spotify's Search tab.
  final bool prominent;

  @override
  _CustomSearchBarState createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CustomSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fieldColor = widget.prominent
        ? Colors.white
        : colorScheme.surfaceContainerHigh;
    final textColor = widget.prominent ? Colors.black : colorScheme.onSurface;
    final hintColor = widget.prominent
        ? const Color(0xFF535353)
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SearchBar(
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        backgroundColor: WidgetStateProperty.all(fieldColor),
        overlayColor: WidgetStateProperty.all(
          colorScheme.primary.withValues(alpha: 0.08),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.prominent ? 6 : 8),
          ),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16),
        ),
        hintText: widget.labelText,
        hintStyle: WidgetStateProperty.all(
          TextStyle(
            color: hintColor,
            fontSize: 16,
            fontWeight: widget.prominent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textStyle: WidgetStateProperty.all(
          TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        leading: Icon(
          FluentIcons.search_24_regular,
          color: widget.prominent ? Colors.black : colorScheme.onSurfaceVariant,
          size: 22,
        ),
        onSubmitted: (String value) {
          widget.onSubmitted(value);
          widget.focusNode.unfocus();
        },
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        controller: widget.controller,
        focusNode: widget.focusNode,
        trailing: [
          if (widget.controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: Icon(
                FluentIcons.dismiss_24_regular,
                color: hintColor,
                size: 20,
              ),
              onPressed: () {
                widget.controller.clear();
                widget.onChanged?.call('');
                widget.focusNode.requestFocus();
              },
            ),
          if (widget.loadingProgressNotifier != null)
            ValueListenableBuilder<bool>(
              valueListenable: widget.loadingProgressNotifier!,
              builder: (_, value, __) {
                if (value) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }
}
