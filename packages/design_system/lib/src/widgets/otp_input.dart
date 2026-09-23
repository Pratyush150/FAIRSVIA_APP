import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Segmented OTP entry: [length] boxes that auto-advance as the user types
/// and auto-backspace. Calls [onChanged] on every edit and [onCompleted]
/// when all boxes are filled.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 4,
    required this.onChanged,
    this.onCompleted,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onChangedAt(int index, String value) {
    if (value.isNotEmpty) {
      AppHaptics.selection();
      if (index < widget.length - 1) _focusNodes[index + 1].requestFocus();
    }
    final code = _value;
    widget.onChanged(code);
    if (code.length == widget.length) {
      AppHaptics.success();
      widget.onCompleted?.call(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: SizedBox(
            width: 56,
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _controllers[index].text.isEmpty &&
                    index > 0) {
                  _focusNodes[index - 1].requestFocus();
                  _controllers[index - 1].clear();
                  widget.onChanged(_value);
                }
              },
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                enabled: widget.enabled,
                autofocus: index == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                // Keep only the most recently typed digit: with `maxLength: 1`
                // a box that already held a digit silently rejected the new
                // one, so a stale digit could never be overwritten (seen on the
                // driver's start-code entry — "1489" became "1481").
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  const _LastDigitFormatter(),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide:
                        BorderSide(color: AppColors.accent, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
                ),
                onChanged: (v) => _onChangedAt(index, v),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Reduces any input to its last character so typing into an already-filled
/// box replaces the digit instead of being dropped.
class _LastDigitFormatter extends TextInputFormatter {
  const _LastDigitFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= 1) return newValue;
    final last = newValue.text.substring(newValue.text.length - 1);
    return TextEditingValue(
      text: last,
      selection: const TextSelection.collapsed(offset: 1),
    );
  }
}
