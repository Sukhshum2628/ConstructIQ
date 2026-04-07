import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Added import for connectivity_plus
import 'router/app_router.dart';
import 'utils/design_tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final container = ProviderContainer();
  
  // Listen for connectivity changes for Phase 5 Offline Sync
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
    if (!results.contains(ConnectivityResult.none)) {
      // Assuming resourceLogServiceProvider is defined elsewhere and accessible via container
      // This line will cause an error if resourceLogServiceProvider is not defined or imported.
      // For the purpose of this edit, I'm adding it as requested.
      // container.read(resourceLogServiceProvider).syncOfflineQueue(); 
      // Placeholder for actual service call, as resourceLogServiceProvider is not in the provided context.
      // If resourceLogServiceProvider is a Provider, it should be imported.
      // For now, commenting it out to avoid compilation errors if it's not defined.
      // You will need to uncomment and ensure `resourceLogServiceProvider` is correctly imported and defined.
      // For example: import 'package:your_app/services/resource_log_service.dart';
      // container.read(resourceLogServiceProvider).syncOfflineQueue();
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ConstructionApp(),
    ),
  );
}

class ConstructionApp extends ConsumerWidget {
  const ConstructionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ConstructIQ Precision',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: DFColors.primary,
        scaffoldBackgroundColor: DFColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: DFColors.primary,
          primary: DFColors.primary,
          surface: DFColors.surface,
          onSurface: DFColors.textPrimary,
          onSurfaceVariant: DFColors.textSecondary,
          outline: DFColors.divider,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: DFColors.background,
          foregroundColor: DFColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: DFTextStyles.screenTitle.copyWith(fontSize: 20),
        ),
        textTheme: TextTheme(
          displayMedium: DFTextStyles.metricHero,
          headlineSmall: DFTextStyles.screenTitle,
          titleSmall: DFTextStyles.sectionHeader,
          bodyMedium: DFTextStyles.body,
          labelSmall: DFTextStyles.caption,
        ),
        dividerTheme: const DividerThemeData(
          color: DFColors.divider,
          thickness: 1,
          space: 1,
        ),
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
