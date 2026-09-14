import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/parent_gate_controller.dart';

/// "Grown-ups only" gate in front of purchases, settings and data controls.
///
/// A calculator-style keypad, because that is the one interaction a parent
/// already knows. First run creates the code; the code is stored only as a
/// salted digest, and five wrong tries start an escalating lockout.
class ParentGateScreen extends ConsumerStatefulWidget {
  const ParentGateScreen({this.returnTo, super.key});

  final String? returnTo;

  @override
  ConsumerState<ParentGateScreen> createState() => _ParentGateScreenState();
}

enum _GateMode { create, confirm, unlock }

class _ParentGateScreenState extends ConsumerState<ParentGateScreen> {
  _GateMode _mode = _GateMode.unlock;
  String _firstEntry = '';
  String _entry = '';
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasPin = await ref.read(parentGateProvider.notifier).hasPin();
      if (!mounted) return;
      setState(() => _mode = hasPin ? _GateMode.unlock : _GateMode.create);
    });
  }

  Future<void> _submit() async {
    if (_entry.length != 4) return;
    setState(() => _busy = true);
    final controller = ref.read(parentGateProvider.notifier);
    try {
      switch (_mode) {
        case _GateMode.create:
          setState(() {
            _firstEntry = _entry;
            _entry = '';
            _mode = _GateMode.confirm;
            _message = null;
          });
        case _GateMode.confirm:
          if (_entry != _firstEntry) {
            setState(() {
              _mode = _GateMode.create;
              _entry = '';
              _firstEntry = '';
              _message = 'Those did not match. Type your code again.';
            });
          } else {
            await controller.setPin(_entry);
            _goAfterUnlock();
          }
        case _GateMode.unlock:
          final result = await controller.verify(_entry);
          if (!mounted) return;
          switch (result) {
            case ParentGateResult.unlocked:
            case ParentGateResult.createdPin:
              _goAfterUnlock();
            case ParentGateResult.wrong:
              setState(() {
                _entry = '';
                _message = AppLocalizations.of(context).parentGateWrong;
              });
            case ParentGateResult.locked:
              setState(() {
                _entry = '';
                _message = 'Too many tries. Wait a minute and try again.';
              });
          }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goAfterUnlock() {
    final target = widget.returnTo;
    if (target == null || target.isEmpty) {
      context.go('/parent');
      return;
    }
    context.go(Uri.decodeComponent(target));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final gate = ref.watch(parentGateProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/home'),
          icon: const Icon(Icons.lock_open_rounded),
          tooltip: 'Back to kid mode',
        ),
        title: Text(l10n.parentGateTitle),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    switch (_mode) {
                      _GateMode.create => l10n.parentGateCreate,
                      _GateMode.confirm => l10n.parentGateConfirm,
                      _GateMode.unlock => l10n.parentGateSubtitle,
                    },
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Dots(count: _entry.length),
                  if (_message case final message?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                  if (gate.isLocked) ...[
                    const SizedBox(height: AppSpacing.md),
                    Badge(
                      label: Text(
                        'Locked ${gate.lockRemaining.inSeconds}s',
                      ),
                      backgroundColor: colors.error,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _Keypad(
                    enabled: !_busy && !gate.isLocked,
                    onTap: (digit) {
                      if (_entry.length >= 4) return;
                      setState(() {
                        _entry += digit;
                        _message = null;
                        if (_entry.length == 4) _submit();
                      });
                    },
                    onBackspace: () => setState(() {
                      if (_entry.isNotEmpty) {
                        _entry = _entry.substring(0, _entry.length - 1);
                      }
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextButton(
                    label: 'Forgot my code',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Reset the grown-up code'),
                        content: const Text(
                          'The code lives only on this tablet, so it cannot be '
                          'emailed to you. You can clear it here — the learner\'s '
                          'progress is untouched. If your family uses a PhonicsAI '
                          'account, reset it from the account email link instead.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.actionCancel),
                          ),
                          FilledButton(
                            onPressed: () async {
                              await ref
                                  .read(parentGateProvider.notifier)
                                  .setPin('0000');
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Code reset to 0000 — change it now.',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: const Text('Reset to 0000'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: AppMotion.fast,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            height: 18,
            width: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? colors.brand : Colors.transparent,
              border: Border.all(
                color: i < count ? colors.brand : colors.inkMuted,
                width: 2,
              ),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onTap,
    required this.onBackspace,
    required this.enabled,
  });

  final ValueChanged<String> onTap;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _Key(
                      label: digit,
                      onTap: enabled ? () => onTap(digit) : null,
                    ),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 84),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _Key(
                label: '0',
                onTap: enabled ? () => onTap('0') : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _Key(
                label: '⌫',
                onTap: enabled ? onBackspace : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      width: 72,
      child: Material(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
