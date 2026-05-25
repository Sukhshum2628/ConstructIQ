import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EngineerShell extends StatelessWidget {
  const EngineerShell({super.key, required this.child});
  final Widget child;

  int _getPageIndex(String location) {
    if (location.startsWith('/my-projects')) return 1;
    if (location.startsWith('/profile-engineer')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _getPageIndex(location);

    return Scaffold(
      body: child,
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
