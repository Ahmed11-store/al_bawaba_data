import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'all_logs_screen.dart';
import 'inspection_screen.dart';
import 'wanted_matches_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;

  // IndexedStack keeps each tab's scroll position / live session
  // table alive when switching tabs, instead of rebuilding from
  // scratch every time (important for the "الفحص" tab, which must
  // not lose the running voice session on tab switch).
  final _screens = const [
    InspectionScreen(),
    WantedMatchesScreen(),
    AllLogsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: AppColors.backgroundAlt,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_none_rounded),
              activeIcon: Icon(Icons.mic_rounded),
              label: 'الفحص',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warning_amber_outlined),
              activeIcon: Icon(Icons.warning_amber_rounded),
              label: 'مطلوبة',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              activeIcon: Icon(Icons.list_alt_rounded),
              label: 'الكل',
            ),
          ],
        ),
      ),
    );
  }
}
