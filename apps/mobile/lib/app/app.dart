import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

/// 界面语言。界面文案只有简体中文（ui-spec），因此固定为 zh-Hans-CN，
/// 同时保证汉字按简体中文字形渲染。
const Locale appLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

/// 声明支持的语言（与 iOS Info.plist 的 CFBundleLocalizations 对应）。
const List<Locale> supportedAppLocales = <Locale>[appLocale, Locale('en')];

/// 卡序 App 根组件：浅色/深色主题跟随系统，文字大小跟随系统缩放。
class CardFlowApp extends ConsumerWidget {
  const CardFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: '卡序',
      debugShowCheckedModeBanner: false,
      theme: buildCardFlowTheme(Brightness.light),
      darkTheme: buildCardFlowTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: appLocale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
