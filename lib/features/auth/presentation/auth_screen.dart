import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/auth_providers.dart';
import '../domain/auth_models.dart';

/// Step 2 — account. Sign in, create, or continue as a guest on this device.
///
/// The guest path is a first-class option, not a nag screen: PhonicsAI is built
/// so a child can start learning before an adult decides about syncing.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(authControllerProvider.notifier);
    final ok = _isSignUp
        ? await controller.signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
          )
        : await controller.signIn(_email.text, _password.text);
    if (ok) _advance();
  }

  Future<void> _guest() async {
    final ok = await ref.read(authControllerProvider.notifier).continueAsGuest();
    if (ok) _advance();
  }

  void _advance() {
    if (!mounted) return;
    context.go('/onboarding/profiles');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final form = ref.watch(authControllerProvider);
    final auth = ref.watch(authStateProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          'Keep progress safe',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'An account lets several grown-up devices share one learner\'s '
          'progress. Skip it and everything simply stays on this tablet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.inkMuted,
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (auth?.isSignedIn ?? false) _SignedInCard(
          user: auth!.user!,
          onContinue: _advance,
          onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
        )
        else ...[
          AppCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.actionSignIn),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.actionSignUp),
                      ),
                    ],
                    selected: {_isSignUp},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) =>
                        setState(() => _isSignUp = values.first),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_isSignUp) ...[
                    AppTextField(
                      label: 'Your name',
                      controller: _name,
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Please add your name'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppTextField(
                    label: 'Email',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.alternate_email_rounded,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Password',
                    controller: _password,
                    isPassword: true,
                    prefixIcon: Icons.lock_outline_rounded,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [
                      AutofillHints.newPassword,
                      AutofillHints.password,
                    ],
                    onSubmitted: (_) => _submit(),
                    validator: _validatePassword,
                  ),
                  if (form.failure case final failure?) ...[
                    const SizedBox(height: AppSpacing.md),
                    _InlineNotice(
                      message: failure.message,
                      tone: _NoticeTone.error,
                    ),
                  ],
                  if (form.notice case final notice?) ...[
                    const SizedBox(height: AppSpacing.md),
                    _InlineNotice(message: notice, tone: _NoticeTone.info),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: _isSignUp ? l10n.actionSignUp : l10n.actionSignIn,
                    isExpanded: true,
                    isLoading: form.isBusy,
                    onPressed: form.isBusy ? null : _submit,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: form.isBusy
                          ? null
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .sendPasswordReset(_email.text),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Continue on this device only',
            icon: Icons.phone_iphone_rounded,
            tone: AppButtonTone.neutral,
            isExpanded: true,
            onPressed: form.isBusy ? null : _guest,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'No AI key or card detail is stored in the app. Purchases run '
              'through Google Play / the App Store.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  static String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'We need an email to protect your account';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email)) {
      return 'That email does not look right';
    }
    return null;
  }

  static String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password';
    if (password.length < 8) return 'Use at least 8 characters';
    return null;
  }
}

class _SignedInCard extends StatelessWidget {
  const _SignedInCard({
    required this.user,
    required this.onContinue,
    required this.onSignOut,
  });

  final AuthUser user;
  final VoidCallback onContinue;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.mint.withValues(alpha: 0.18),
                child: Icon(
                  user.isGuest
                      ? Icons.phone_iphone_rounded
                      : Icons.verified_user_rounded,
                  color: colors.mint,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.isGuest ? 'This device' : user.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      user.email ?? 'Progress stays on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Continue', isExpanded: true, onPressed: onContinue),
          const SizedBox(height: AppSpacing.sm),
          AppTextButton(
            label: 'Not you? Sign out',
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}

enum _NoticeTone { error, info }

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, required this.tone});

  final String message;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isError = tone == _NoticeTone.error;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (isError ? colors.error : colors.sky).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: isError ? colors.error : colors.sky,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isError ? colors.error : colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
