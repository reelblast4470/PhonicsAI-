import 'package:flutter/widgets.dart';

/// Locales the interface can render. Each entry maps to a `.arb` file in
/// `lib/l10n/`; untranslated copy falls back to English rather than crashing.
@immutable
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.flag,
    this.direction = TextDirection.ltr,
  });

  final String code;
  final String nativeName;
  final String englishName;
  final String flag;
  final TextDirection direction;

  bool get isRtl => direction == TextDirection.rtl;

  Locale get locale => Locale(code);

  static const List<AppLanguage> supported = [
    AppLanguage(
      code: 'en',
      nativeName: 'English',
      englishName: 'English',
      flag: '🇬🇧',
    ),
    AppLanguage(
      code: 'es',
      nativeName: 'Español',
      englishName: 'Spanish',
      flag: '🇪🇸',
    ),
    AppLanguage(
      code: 'hi',
      nativeName: 'हिन्दी',
      englishName: 'Hindi',
      flag: '🇮🇳',
    ),
  ];

  static AppLanguage? fromCode(String? code) {
    if (code == null) return null;
    for (final language in supported) {
      if (language.code == code) return language;
    }
    return null;
  }

  static String labelFor(String? code) {
    final language = fromCode(code);
    return language == null ? 'Device default' : '${language.flag}  ${language.nativeName}';
  }
}

/// Languages a household may use to *explain* things to the child. Wider than
/// the UI locale list because the tutor can instruct in a language the app UI
/// does not have yet.
abstract final class InstructionLanguage {
  static const Map<String, String> names = {
    'en': 'English',
    'hi': 'हिन्दी (Hindi)',
    'es': 'Español (Spanish)',
    'ta': 'தமிழ் (Tamil)',
    'te': 'తెలుగు (Telugu)',
    'bn': 'বাংলা (Bengali)',
    'mr': 'मराठी (Marathi)',
    'gu': 'ગુજરાતી (Gujarati)',
    'ar': 'العربية (Arabic)',
  };

  static List<String> get codes => names.keys.toList(growable: false);
}
