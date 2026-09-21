import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/browser_screen.dart';
import 'services/bookmark_store.dart';
import 'services/overlay_store.dart';
import 'services/settings_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.wood,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final settings = SettingsStore();
  final bookmarks = BookmarkStore();
  final overlays = OverlayStore();
  await settings.load();
  await bookmarks.load();
  await overlays.load();
  runApp(
    BrowserTranslatorApp(
      settings: settings,
      bookmarks: bookmarks,
      overlays: overlays,
    ),
  );
}

class BrowserTranslatorApp extends StatelessWidget {
  const BrowserTranslatorApp({
    super.key,
    required this.settings,
    required this.bookmarks,
    required this.overlays,
  });

  final SettingsStore settings;
  final BookmarkStore bookmarks;
  final OverlayStore overlays;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '瀏覽器翻譯',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: BrowserScreen(
        settings: settings,
        bookmarks: bookmarks,
        overlays: overlays,
      ),
    );
  }
}
