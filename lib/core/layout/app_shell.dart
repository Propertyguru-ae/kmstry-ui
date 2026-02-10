import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/people/presentation/people_page.dart';
import 'package:kmstry_frontend/features/messages/presntation/messages.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  String _userInitial = 'D';
  int _unreadNotificationCount = 0;
  final NotificationRepository _notificationRepo = NotificationRepository();

  final GlobalKey<DmListPageState> _dmListKey = GlobalKey<DmListPageState>(); // ignore: library_private_types_in_public_api

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const VenueHomePage(),
      const NotificationPage(),
      DmListPage(key: _dmListKey),
      const PeoplePage(),
      const ProfilePage(),
    ];
    _loadUserInitial();
    _loadUnreadNotificationCount();
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final list = await _notificationRepo.getNotifications(limit: 50);
      if (!mounted) return;
      final count = list.where((n) => !n.isRead).length;
      setState(() => _unreadNotificationCount = count);
    } catch (_) {}
  }

  final List<String> _userVenues = ['VenueA', 'VenueB'];
  String _activeAccount = 'Personal';


  Future<void> _loadUserInitial() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      final fullName = me['full_name'] as String?;
      if (fullName != null && fullName.isNotEmpty) {
        setState(() {
          _userInitial = fullName[0].toUpperCase();
        });
      }
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await AuthRepository().logout();
      if (!context.mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        AuthRoutes.login,
        (route) => false,
      );
    } catch (_) {}
  }

  void _onItemTapped(int index) {
    if (index == 4 && _currentIndex == 4) {
      _showAccountSwitcher(context);
    } else {
      if (index == 2) {
        _dmListKey.currentState?.loadChats();
      }
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _showAccountSwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ..._userVenues.map((venue) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.black12,
                        child: Icon(Icons.storefront, color: Colors.black),
                      ),
                      title: Text(venue,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: _activeAccount == venue
                          ? const Icon(Icons.check_circle, color: Colors.blue)
                          : null,
                      onTap: () {
                        setState(() => _activeAccount = venue);
                        Navigator.pop(context);
                      },
                    )),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Account Settings'),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Switch to Personal'),
                  onTap: () {
                    setState(() => _activeAccount = 'Personal');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
                  title: const Text('Add Venue',
                      style: TextStyle(
                          color: Colors.blue, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Log out',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _logout(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileAvatar({required bool isActive}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? Colors.black : Colors.transparent,
          width: 2,
        ),
        color: Colors.grey.shade200,
      ),
      alignment: Alignment.center,
      child: Text(
        _userInitial,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationUnreadScope(
      unreadCount: _unreadNotificationCount,
      updateUnreadCount: (count) {
        if (_unreadNotificationCount != count) {
          setState(() => _unreadNotificationCount = count);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: _pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.white.withOpacity(0.95),
          elevation: 0,
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey.shade400,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          onTap: _onItemTapped,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, size: 30),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _buildNotificationIcon(),
              label: '',
            ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.mark_chat_unread_outlined, // Instagram DM stili
              size: 28,
            ),
            label: '',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline, size: 30),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: _buildProfileAvatar(isActive: _currentIndex == 4),
            label: '',
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildNotificationIcon() {
    const icon = Icon(Icons.notifications_none, size: 30);
    if (_unreadNotificationCount <= 0) {
      return icon;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -4,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
