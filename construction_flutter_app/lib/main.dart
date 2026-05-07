import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Added import for connectivity_plus
import 'package:google_fonts/google_fonts.dart';
import 'router/app_router.dart';
import 'utils/design_tokens.dart';
import 'services/ml_predictor_service.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('APP_START: Binding initialized.');

    await Firebase.initializeApp();
    debugPrint('APP_START: Firebase initialized.');

    // Force portrait mode only
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint('APP_START: Orientations set.');
    
    // Pre-load on-device ML model
    final mlService = mlPredictorService;
    mlService.loadModel();
    debugPrint('APP_START: ML Model loading started.');
    
    final container = ProviderContainer();
    
    // Listen for connectivity changes for Phase 5 Offline Sync
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      debugPrint('APP_CONNECTIVITY: Status changed to $results');
      if (!results.contains(ConnectivityResult.none)) {
        // Sync logic placeholder
      }
    });

    debugPrint('APP_START: Running app...');
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const ConstructionApp(),
      ),
    );
  } catch (e, stack) {
    debugPrint('FATAL_CRASH: $e');
    debugPrint('STACK_TRACE: $stack');
    
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text('CRITICAL STARTUP ERROR', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(e.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => main(), 
                    child: const Text('RETRY'),
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
        textTheme: GoogleFonts.interTextTheme().copyWith(
          displayMedium: DFTextStyles.metricHero,
          headlineSmall: DFTextStyles.screenTitle,
          titleMedium: DFTextStyles.sectionHeader,
          titleSmall: DFTextStyles.cardTitle,
          bodyLarge: DFTextStyles.body.copyWith(fontSize: 16),
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
