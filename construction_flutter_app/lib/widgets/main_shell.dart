import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/design_tokens.dart';

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter.of(context);
    final String location = router.routerDelegate.currentConfiguration.uri.path;

    return Scaffold(
      body: child,
      bottomNavigationBar: _buildBottomNav(context, location),
    );
  }

  Widget _buildBottomNav(BuildContext context, String location) {
    return Container(
      decoration: BoxDecoration(
        color: DFColors.background,
        border: const Border(
          top: BorderSide(color: DFColors.divider, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _getSelectedIndex(location),
        onTap: (index) => _onItemTapped(context, index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: DFColors.primary,
        unselectedItemColor: DFColors.textSecondary,
        selectedLabelStyle: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle: DFTextStyles.caption.copyWith(fontSize: 10),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Projects',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology_outlined),
            activeIcon: Icon(Icons.psychology),
            label: 'Assistant',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }

  int _getSelectedIndex(String location) {
    if (location.startsWith('/manager-dashboard') || location.startsWith('/engineer-home')) return 0;
    if (location.startsWith('/projects') || location.startsWith('/project/')) return 1;
    if (location.startsWith('/ai-chat')) return 2;
    if (location.startsWith('/analytics')) return 3;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/manager-dashboard'); 
        break;
      case 1:
        context.go('/projects');
        break;
      case 2:
        context.go('/ai-chat');
        break;
      case 3:
        context.go('/analytics');
        break;
    }
  }
}
