import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'router/app_router.dart';
import 'utils/design_tokens.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/ml_predictor_service.dart';
import 'services/push_service.dart';
import 'providers/logging_provider.dart';
import 'firebase_options.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('APP_START: Binding initialized.');

    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
    }
    debugPrint('APP_START: Firebase initialized.');

    if (!kIsWeb) {
      // Remote push (FCM): background handler + client registration.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await PushService.init();
      debugPrint('APP_START: Push service initialized.');

      // Force portrait mode only on mobile
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      debugPrint('APP_START: Orientations set.');
    } else {
      await PushService.init();
    }
    
    // Pre-load on-device ML model
    final mlService = mlPredictorService;
    mlService.loadModel();
    debugPrint('APP_START: ML Model loading started.');
    
    final container = ProviderContainer();

    // Flush any logs queued while offline (from a previous session).
    container.read(loggingServiceProvider).processQueue();

    // And flush again whenever connectivity is regained (Phase 5 offline sync).
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      debugPrint('APP_CONNECTIVITY: Status changed to $results');
      if (!results.contains(ConnectivityResult.none)) {
        container.read(loggingServiceProvider).processQueue();
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
      builder: (context, child) {
        if (!kIsWeb) return child ?? const SizedBox.shrink();
        return Scaffold(
          body: Column(
            children: [
              const _WebPreviewBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }
}

class _WebPreviewBanner extends StatelessWidget {
  const _WebPreviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A237E), // deep navy — matches ConstructIQ theme
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.amber,
            size: 16,
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '📱 Web Preview — ConstructIQ is a mobile application. '
              'This demo may differ slightly from the actual app experience.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
