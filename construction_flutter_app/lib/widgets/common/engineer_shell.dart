import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class EngineerShell extends ConsumerWidget {
  const EngineerShell({super.key, required this.child});
  final Widget child;

  int _getPageIndex(String location) {
    if (location.startsWith('/my-projects')) return 1;
    if (location.startsWith('/profile-engineer')) return 2;
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
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == currentIndex) return;
          switch (index) {
            case 0:
              context.go('/engineer-home');
              break;
            case 1:
              context.go('/my-projects');
              break;
            case 2:
              context.go('/profile-engineer');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment),
            label: 'My Projects',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
