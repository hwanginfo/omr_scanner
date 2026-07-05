import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'database/database_helper.dart';
import 'pages/home_page.dart';
import 'pages/class_management_page.dart';
import 'pages/template_management_page.dart';
import 'pages/statistics_page.dart';
import 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize database
  await DatabaseHelper().database;
  runApp(const OmrScannerApp());
}

class OmrScannerApp extends StatelessWidget {
  const OmrScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MyAppState(),
      child: MaterialApp(
        title: 'OMR 答题卡阅卷',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        home: const HomePage(),
        routes: {
          '/class-management': (_) => const ClassManagementPage(),
          '/template-management': (_) => const TemplateManagementPage(),
          '/statistics': (_) => const StatisticsPage(),
          '/settings': (_) => const SettingsPage(),
        },
      ),
    );
  }
}

/// Global application state (renamed from AppState to avoid conflict with flutter_document_scanner).
class MyAppState extends ChangeNotifier {
  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;

  void setTab(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }
}
