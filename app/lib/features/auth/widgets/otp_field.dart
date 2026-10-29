import 'package:material_ui/material_ui.dart';

import '../../../core/input.dart';
import '../../../core/theme/tokens.dart';

const otpLength = 6;

/// Six boxes drawn over one real text field, so SMS autofill, paste and screen readers see a single input.
class OtpField extends StatelessWidget {
  const OtpField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    const none = InputBorder.none;
    return Stack(
      children: [
        ExcludeSemantics(
          child: ListenableBuilder(
            listenable: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final code = controller.text;
              return Row(
                spacing: Space.sm,
                children: [
                  for (var i = 0; i < otpLength; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: Motion.fast,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surfaceContainer,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(
                            width: 1.5,
                            color: hasError
                                ? c.error
                                : focusNode.hasFocus && i == code.length.clamp(0, otpLength - 1)
                                    ? c.primary
                                    : c.surfaceContainer,
                          ),
                        ),
                        child: Text(
                          i < code.length ? code[i] : '',
                          style: t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            autocorrect: false,
            enableSuggestions: false,
            // a pasted SMS ("123456 is your code") keeps just the code
            inputFormatters: const [DigitsFormatter(otpLength)],
            showCursor: false,
            style: const TextStyle(color: Colors.transparent),
            decoration: const InputDecoration(
              labelText: '6-digit code',
              labelStyle: TextStyle(color: Colors.transparent),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              filled: false,
              border: none,
              enabledBorder: none,
              focusedBorder: none,
              disabledBorder: none,
              errorBorder: none,
              counterText: '',
            ),
            onChanged: (v) {
              if (v.length == otpLength) onCompleted(v);
            },
          ),
        ),
      ],
    );
  }
}
