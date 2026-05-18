import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../screens/dashboard/engineer_home.dart';
import '../../screens/projects/project_list_screen.dart';
import '../../screens/profile/profile_screen.dart';

class EngineerShell extends StatefulWidget {
  const EngineerShell({super.key, required this.child});
  final Widget child;

  @override
  State<EngineerShell> createState() => _EngineerShellState();
}

class _EngineerShellState extends State<EngineerShell> {
  bool _initialized = false;
  late PageController _pageController;
  int _currentIndex = 0;

  int _getPageIndex(String location) {
    if (location.startsWith('/my-projects')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  void _syncRoute(int index) {
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final location = GoRouterState.of(context).matchedLocation;
      _currentIndex = _getPageIndex(location);
      _pageController = PageController(initialPage: _currentIndex);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final targetIndex = _getPageIndex(location);

    if (_initialized && _pageController.hasClients && _currentIndex != targetIndex) {
      _currentIndex = targetIndex;
      _pageController.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          if (index == _currentIndex) return;
          setState(() {
            _currentIndex = index;
          });
          _syncRoute(index);
        },
        physics: const ClampingScrollPhysics(), // Premium smooth horizontal swiping
        children: const [
          EngineerHome(),
          ProjectListScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == _currentIndex) return;
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
          );
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
