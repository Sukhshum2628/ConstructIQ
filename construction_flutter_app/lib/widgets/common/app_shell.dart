import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/design_tokens.dart';
import '../../screens/dashboard/manager_dashboard.dart';
import '../../screens/projects/project_list_screen.dart';
import '../../screens/analytics/manager_analytics.dart';
import '../../screens/reports/report_screen.dart';
import '../../screens/profile/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _initialized = false;
  late PageController _pageController;
  int _currentIndex = 0;

  int _getPageIndex(String location) {
    if (location.startsWith('/projects')) return 1;
    if (location.startsWith('/analytics')) return 2;
    if (location.startsWith('/reports')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _syncRoute(int index) {
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
          ManagerDashboard(),
          ProjectListScreen(),
          ManagerAnalytics(),
          ReportScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: DFColors.surface,
        indicatorColor: DFColors.primaryLight,
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
