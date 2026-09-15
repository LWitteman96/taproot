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
    this.hint,
    this.maxLines = 1,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  State<DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<DraftTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Replaces the text from outside the field — used when a suggestion is
  /// tapped rather than typed. Keeps the cursor at the end of the new value.
  void setText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
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
