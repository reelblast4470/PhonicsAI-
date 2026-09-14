import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// Labeled text field with an inline error, a 52dp minimum height and, for
/// password fields, a reveal toggle. Grown-up screens only — children never
/// type prose in this app.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.isPassword = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.autofocus = false,
    this.enabled = true,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool isPassword;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? Function(String?)? validator;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final bool autofocus;
  final bool enabled;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.isPassword;
  final FocusNode _focus = FocusNode();
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return TextFormField(
      controller: widget.controller,
      focusNode: _focus,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      autofillHints: widget.autofillHints == null
          ? null
          : List<String>.from(widget.autofillHints!),
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: (value) {
        final error = widget.validator?.call(value);
        // Mirror the validator result into the label colour so the field is
        // still obvious with a screen reader or in high-contrast mode.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasError = error != null);
        });
        return error;
      },
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        alignLabelWithHint: true,
        errorStyle: const TextStyle(height: 1.4, fontSize: 12.5),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Icon(
                  widget.prefixIcon,
                  size: 20,
                  color: _hasError ? colors.error : colors.inkMuted,
                ),
              ),
        suffixIcon: widget.isPassword
            ? IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                ),
                tooltip: _obscured ? 'Show password' : 'Hide password',
              )
            : null,
      ),
    );
  }
}
