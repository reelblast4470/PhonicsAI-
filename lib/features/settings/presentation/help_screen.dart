import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/kid_scaffold.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../application/support_service.dart';

/// Help & support. Offline-capable FAQ (bundled content, searchable) plus a
/// contact path that goes through our own API — never an embedded web view.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _search = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _query = '';
  bool _sending = false;
  FaqEntry? _open;

  @override
  void dispose() {
    _search.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  List<FaqEntry> get _matches {
    final all = SupportContent.faq;
    if (_query.trim().isEmpty) return all;
    final needle = _query.toLowerCase().trim();
    return all
        .where((entry) =>
            entry.question.toLowerCase().contains(needle) ||
            entry.answer.toLowerCase().contains(needle) ||
            entry.tags.any((tag) => tag.contains(needle)))
        .toList(growable: false);
  }

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      AppToast.show(
        context,
        'Add a subject and a message first.',
        isError: true,
      );
      return;
    }
    setState(() => _sending = true);
    final config = ref.read(appConfigProvider);
    final result = config.hasBackend
        ? await ref.read(supportServiceProvider).send(
            subject: _subject.text,
            body: _body.text,
            locale: Localizations.localeOf(context).languageCode,
          )
        : await ref.read(supportServiceProvider).send(
            subject: _subject.text,
            body: _body.text,
            locale: 'en',
          );
    if (!mounted) return;
    setState(() => _sending = false);
    result.fold(
      ok: (_) {
        _subject.clear();
        _body.clear();
        AppToast.show(
          context,
          AppLocalizations.of(context).helpSent,
          icon: Icons.mark_email_read_outlined,
        );
      },
      fail: (failure) => AppToast.show(
        context,
        failure.message,
        isError: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final matches = _matches;

    return KidScaffold(
      title: l10n.helpTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: l10n.helpSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.actionClose,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Common questions', leadingIcon: Icons.help_outline_rounded),
          if (matches.isEmpty)
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.search_off_rounded, color: colors.inkMuted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(l10n.helpEmpty)),
                ],
              ),
            )
          else
            for (final entry in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _FaqTile(
                  entry: entry,
                  isOpen: _open?.id == entry.id,
                  onToggle: () => setState(
                    () => _open = _open?.id == entry.id ? null : entry,
                  ),
                ),
              ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Still stuck?', leadingIcon: Icons.mail_outline_rounded),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Write to us and a human replies. Include the age of your '
                  'learner and what you were doing when it went wrong.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _body,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: l10n.helpSend,
                        icon: Icons.send_rounded,
                        isExpanded: true,
                        isCompact: true,
                        isLoading: _sending,
                        onPressed: _sending ? null : _send,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      onPressed: () => AppToast.show(
                        context,
                        l10n.helpContactBody,
                        icon: Icons.alternate_email_rounded,
                      ),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy support address',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.helpNoConnection,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.entry,
    required this.isOpen,
    required this.onToggle,
  });

  final FaqEntry entry;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      onTap: onToggle,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: colors.brand,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  entry.question,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            alignment: Alignment.topCenter,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.answer,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (entry.actionLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Wrap(
                              children: [
                                ActionChip(
                                  label: Text(entry.actionLabel!),
                                  onPressed: entry.onAction == null
                                      ? null
                                      : () => entry.onAction!(),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
