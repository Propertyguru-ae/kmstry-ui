import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    VenueHomePage(),
    SizedBox(),
    SizedBox(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // app_shell.dart içindeki Scaffold kısmını şu şekilde güncelle:
    return Scaffold(
      extendBody: true, // İçeriğin navbar altına girmesini sağlar
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        // Navbar'ın arkasını hafif flulaştırmak veya şeffaf yapmak için
        decoration: const BoxDecoration(color: Colors.transparent),
        child: BottomNavigationBar(
          backgroundColor: Colors.white.withOpacity(0.9), // Yarı şeffaf beyaz
          elevation: 0,
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none),
              label: 'Notifications',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'DMs',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
