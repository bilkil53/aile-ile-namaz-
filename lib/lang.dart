import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Uygulama dili: telefonun diline göre (varsayılan), Türkçe ya da İngilizce.
/// Telefon dili Türkçe değilse uygulama İngilizce açılır.
enum AppLang { system, tr, en }

class Lang {
  static const _key = 'lang';

  /// Dil değişince uygulama ekranları yeniden çizilir.
  static final changed = ValueNotifier<int>(0);

  static AppLang get choice {
    try {
      return switch (AppSettings.prefs.getString(_key)) {
        'tr' => AppLang.tr,
        'en' => AppLang.en,
        _ => AppLang.system,
      };
    } catch (_) {
      return AppLang.system; // ayarlar henüz yüklenmediyse (ör. birim testleri)
    }
  }

  /// Etkin dil kodu: 'tr' ya da 'en'.
  static String get code => switch (choice) {
        AppLang.tr => 'tr',
        AppLang.en => 'en',
        AppLang.system => systemCode,
      };

  static String get systemCode => PlatformDispatcher.instance.locale.languageCode == 'tr' ? 'tr' : 'en';

  static bool get isEn => code == 'en';

  static Future<void> set(AppLang l) async {
    if (l == AppLang.system) {
      await AppSettings.prefs.remove(_key);
    } else {
      await AppSettings.prefs.setString(_key, l.name);
    }
    changed.value++;
  }

  /// Ayarlar'da gösterilen ad (her dil kendi adıyla yazılır).
  static String label(AppLang l) => switch (l) {
        AppLang.system => t('Telefonun diline göre', 'Same as phone'),
        AppLang.tr => 'Türkçe',
        AppLang.en => 'English',
      };
}

/// Metnin Türkçesi ve İngilizcesi yan yana yazılır; etkin dile göre biri gösterilir.
String t(String tr, String en) => Lang.isEn ? en : tr;
