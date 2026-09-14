import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';

/// `context.l10n.navHome` everywhere instead of
/// `AppLocalizations.of(context)!.navHome` (null-free thanks to
/// `nullable-getter: false` in l10n.yaml).
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
