import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/auth_provider.dart';
import '../providers/project_provider.dart';
import '../models/user_model.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/dashboard/manager_dashboard.dart';
import '../screens/dashboard/engineer_home.dart';
import '../screens/dashboard/owner_dashboard.dart';
import '../screens/projects/project_list_screen.dart';
import '../screens/projects/project_detail_screen.dart';
import '../screens/projects/create_project_screen.dart';
import '../screens/estimation/cad_upload_screen.dart';
import '../screens/logging/log_entry_screen.dart';
import '../screens/logging/log_history_screen.dart';
import '../screens/ai_assistant/ai_chat_screen.dart';
import '../screens/analytics/manager_analytics.dart';
import '../screens/reports/pdf_preview_screen.dart';
import '../screens/reports/report_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/notifications/notification_centre_screen.dart';
import '../screens/teams/team_panel_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/safety/safety_screen.dart';
import '../screens/ai/project_analyst_screen.dart';
import '../screens/workforce/workforce_overview_screen.dart';
import '../screens/finance/bill_upload_screen.dart';
import '../screens/auth/access_denied_screen.dart';
import '../widgets/common/app_shell.dart';
import '../widgets/common/engineer_shell.dart';

// ── Navigator Keys ── created once, never recreated
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  RouterNotifier(this._ref) {
    _ref.listen(authStateChangesProvider, (previous, next) {
      // If logging out or switching accounts, invalidate all user state and selections
      if (next.value == null || (previous != null && previous.value?.uid != next.value?.uid)) {
        _ref.invalidate(selectedProjectIdProvider);
        _ref.invalidate(selectedDashboardProjectIdProvider);
      }
      _ref.invalidate(userProfileProvider);
      notifyListeners();
    });
    
    _ref.listen(userProfileProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final _routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>(
  (ref) => RouterNotifier(ref),
);

// ── Single GoRouter instance ── NEVER recreated after first build
final routerProvider = Provider<GoRouter>((ref) {
  // We use ref.read because we don't want to recreate GoRouter when the notifier changes.
  // GoRouter will listen to the refreshListenable itself and trigger redirects.
  final notifier = ref.read(_routerNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: '/login',
    debugLogDiagnostics: true,

    redirect: (context, state) {
      debugPrint('ROUTER: Redirecting for ${state.matchedLocation}');
      final user = FirebaseAuth.instance.currentUser;
      final isAuthPath = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (user == null) {
        debugPrint('ROUTER: No user detected');
        return isAuthPath ? null : '/login';
      }

      // ── Synchronization Guard ──
      // Halt routing redirect cycle until Riverpod's internal auth state matches the physical Firebase Auth state.
      final authState = ref.read(authStateChangesProvider);
      if (authState.isLoading || !authState.hasValue || authState.value?.uid != user.uid) {
        debugPrint('ROUTER: Auth state changes provider out of sync (current: ${authState.value?.uid}, physical: ${user.uid}). Waiting...');
        return null; // Halt redirect, stay on splash/loading
      }

      // Instead of manual GET, use the existing provider state
      final profileAsync = ref.read(userProfileProvider);
      
      // If profile is still loading or hasn't been fetched, don't redirect yet.
      // This prevents the "Default to Engineer" bug on slow connections.
      if (profileAsync.isLoading || !profileAsync.hasValue) {
        debugPrint('ROUTER: Waiting for profile data...');
        return null;
      }

      if (profileAsync.hasError) {
        debugPrint('ROUTER ERROR: Profile state has error: ${profileAsync.error}');
        if (profileAsync.error.toString().contains('permission-denied')) {
          return '/access-denied';
        }
        return isAuthPath ? null : '/login';
      }

      final profile = ref.read(currentUserProfileProvider);
      // ── Stale Profile Guard ──
      // Halt redirect if the profile fetched belongs to a different/previous user.
      if (profile != null && profile.uid != user.uid) {
        debugPrint('ROUTER: Stale profile UID detected (${profile.uid} != ${user.uid}). Waiting...');
        return null; // Halt redirect
      }

      if (profile == null) {
        debugPrint('ROUTER: Profile not found in Firestore');
        return (state.matchedLocation == '/role-selection') ? null : '/role-selection';
      }

      final role = profile.role;
      debugPrint('ROUTER: User role verified as ${role.name}');

      if (isAuthPath || state.matchedLocation == '/role-selection') {
        if (role == UserRole.manager || role == UserRole.admin || role == UserRole.owner) return '/dashboard';
        return '/engineer-home';
      }

      return null;
    },

    routes: [
      // ── Auth routes (no shell)
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/role-selection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/access-denied',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AccessDeniedScreen(error: 'Permission Denied'),
      ),

      // ── Shell with bottom nav (Manager + Admin)
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const ManagerDashboard(),
          ),
          GoRoute(
            path: '/projects',
            builder: (context, state) => const ProjectListScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const ManagerAnalytics(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Shell for Engineer
      ShellRoute(
        navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'engineerShell'),
        builder: (context, state, child) => EngineerShell(child: child),
        routes: [
          GoRoute(
            path: '/engineer-home',
            builder: (context, state) => const EngineerHome(),
          ),
          GoRoute(
            path: '/my-projects',
            builder: (context, state) => const ProjectListScreen(),
          ),
          GoRoute(
            path: '/profile-engineer',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Owner Route
      GoRoute(
        path: '/owner-home',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OwnerDashboard(),
      ),

      // ── Root-level routes (no shell, full screen)
      GoRoute(
        path: '/projects/:projectId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final pId = state.pathParameters['projectId']!;
          return ProjectDetailScreen(projectId: pId);
        },
        routes: [
          GoRoute(
            path: 'log-entry',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return LogEntryScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'cad-upload',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return CadUploadScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'ai-chat',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return AiChatScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'pdf-preview',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return PdfPreviewScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'team',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return TeamPanelScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'workforce',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return WorkforceOverviewScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'schedule',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return ScheduleScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'inventory',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return InventoryScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'safety',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return SafetyScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'analyst',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return ProjectAnalystScreen(projectId: projectId);
            },
          ),
          GoRoute(
            path: 'bills/upload',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final projectId = state.pathParameters['projectId']!;
              return BillUploadScreen(projectId: projectId);
            },
          ),
        ],
      ),

      GoRoute(
        path: '/create-project',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CreateProjectScreen(),
      ),

      GoRoute(
        path: '/log-history/:projectId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final projectId = state.pathParameters['projectId']!;
          return LogHistoryScreen(projectId: projectId);
        },
      ),


      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationCentreScreen(),
      ),
    ],
  );
});
