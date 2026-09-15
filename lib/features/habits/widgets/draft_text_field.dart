import 'package:flutter/material.dart';

/// A text field that seeds itself from the draft once, then reports changes.
///
/// The draft lives in the controller, and every keystroke rebuilds the step
/// that holds this field. Rebuilding a `TextFormField` from `initialValue`
/// would move the cursor to the end on every character, so the
/// [TextEditingController] is owned here and seeded only when the field is
/// first built — which is also what makes stepping back to an earlier screen
/// show what was typed there.
class DraftTextField extends StatefulWidget {
  const DraftTextField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.controller,
    this.hint,
    this.maxLines = 1,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final String label;

  /// Seeds the field the first time it is built. Ignored when [controller] is
  /// supplied — the owner has already seeded it.
  final String initialValue;

  /// Supplied when the parent needs to write into the field itself, as the cue
  /// step does when an example is tapped rather than typed. The parent owns and
  /// disposes it.
  final TextEditingController? controller;

  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  State<DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<DraftTextField> {
  late final TextEditingController _owned =
      widget.controller ?? TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    // Only what this widget made. A controller handed in belongs to the parent
    // and is still in use after this field is gone.
    if (widget.controller == null) _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _owned,
    onChanged: widget.onChanged,
    autofocus: widget.autofocus,
    maxLines: widget.maxLines,
    textCapitalization: widget.textCapitalization,
    textInputAction: widget.maxLines == 1
        ? TextInputAction.next
        : TextInputAction.newline,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      border: const OutlineInputBorder(),
    ),
  );
}
