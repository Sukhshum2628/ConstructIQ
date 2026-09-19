import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/design_tokens.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  int _getPageIndex(String location) {
    if (location.startsWith('/projects')) return 1;
    if (location.startsWith('/analytics')) return 2;
    if (location.startsWith('/reports')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _getPageIndex(location);
    final isDemoMode = ref.watch(isDemoModeProvider);

    return Scaffold(
      body: Column(
        children: [
          if (isDemoMode)
            Material(
              color: const Color(0xFF1A237E),
              elevation: 4,
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('🔍', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Demo Mode — Data is simulated. Sign up to use real project data.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () async {
                          await ref.read(authServiceProvider).signOutDemo();
                          if (context.mounted) {
                            context.go('/register');
                          }
                        },
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: DFColors.surface,
        indicatorColor: DFColors.primaryLight,
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == currentIndex) return;
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.go('/projects');
              break;
            case 2:
              context.go('/analytics');
              break;
            case 3:
              context.go('/reports');
              break;
            case 4:
              context.go('/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, color: DFColors.textSecondary),
            selectedIcon: Icon(Icons.dashboard, color: DFColors.primary),
            label: 'Command',
          ),
          NavigationDestination(
            icon: Icon(Icons.architecture_outlined, color: DFColors.textSecondary),
            selectedIcon: Icon(Icons.architecture, color: DFColors.primary),
            label: 'Missions',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined, color: DFColors.textSecondary),
            selectedIcon: Icon(Icons.analytics, color: DFColors.primary),
            label: 'Intelligence',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined, color: DFColors.textSecondary),
            selectedIcon: Icon(Icons.description, color: DFColors.primary),
            label: 'Archive',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: DFColors.textSecondary),
            selectedIcon: Icon(Icons.person, color: DFColors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
