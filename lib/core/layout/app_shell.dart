import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/people/presentation/people_page.dart';
import 'package:kmstry_frontend/features/messages/presntation/messages.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_profile_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  String _userInitial = 'D';
  int _unreadNotificationCount = 0;
  final NotificationRepository _notificationRepo = NotificationRepository();

  final GlobalKey<DmListPageState> _dmListKey =
      GlobalKey<
        DmListPageState
      >(); // ignore: library_private_types_in_public_api

  bool _isVenueContext = false;
  bool _hasPersonalProfile = false;
  String _personalAccountLabel = 'Personal';

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    _loadUserInitial();
    _loadUnreadNotificationCount();
    PushManager.instance.reconcileNotificationState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushManager.instance.reconcileNotificationState();
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final list = await _notificationRepo.getNotifications(limit: 50);
      if (!mounted) return;
      final count = list.where((n) => !n.isRead).length;
      setState(() => _unreadNotificationCount = count);
    } catch (_) {}
  }

  final List<MemberVenue> _memberVenues = [];
  String _activeAccount = 'Personal';

  Future<void> _loadUserInitial() async {
    try {
      final me = await AuthRepository().getMe();
      final context = MeContextModel.fromMe(me);
      if (!mounted) return;
      final fullName = (me['fullName'] ?? me['full_name'])?.toString().trim();
      String activeLabel = 'Personal';
      final lastContext = context.lastActiveContext?.toUpperCase();
      final hasVenueContext =
          context.hasVenueMembership || context.memberVenues.isNotEmpty;
      String? resolvedVenueId = context.activeVenueId;
      if (resolvedVenueId == null ||
          resolvedVenueId.isEmpty ||
          !context.memberVenues.any((venue) => venue.id == resolvedVenueId)) {
        resolvedVenueId = context.memberVenues.isNotEmpty
            ? context.memberVenues.first.id
            : null;
      }
      if (lastContext == 'VENUE' && resolvedVenueId != null) {
        for (final venue in context.memberVenues) {
          if (venue.id == resolvedVenueId) {
            activeLabel = venue.name;
            break;
          }
        }
      } else if (lastContext == 'VENUE' && context.memberVenues.isNotEmpty) {
        activeLabel = context.memberVenues.first.name;
      }
      setState(() {
        if (fullName != null && fullName.isNotEmpty) {
          _userInitial = fullName[0].toUpperCase();
        }
        _isVenueContext = lastContext == 'VENUE' && hasVenueContext;
        _hasPersonalProfile = context.hasPersonalProfile;
        _personalAccountLabel = fullName != null && fullName.isNotEmpty
            ? fullName
            : 'Personal';
        _memberVenues
          ..clear()
          ..addAll(context.memberVenues);
        _activeAccount = activeLabel;
        if (_isVenueContext && _currentIndex > 2) {
          _currentIndex = 0;
        }
      });
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await AuthRepository().logout();
      if (!context.mounted) return;

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
    } catch (_) {}
  }

  Future<void> _switchToPersonal() async {
    await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
    if (!mounted) return;
    if (!_hasPersonalProfile) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NameDobOnboardingPage()),
      );
      return;
    }
    Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
  }

  Future<void> _switchToVenue(MemberVenue venue) async {
    await AuthRepository().switchContext(
      lastActiveContext: 'VENUE',
      activeVenueId: venue.id,
    );
    if (!mounted) return;
    setState(() {
      _isVenueContext = true;
      _activeAccount = venue.name;
      _currentIndex = 0;
    });
    _loadUnreadNotificationCount();
  }

 void _onItemTapped(int index) {
  if (!_isVenueContext && index == 2) {
    _dmListKey.currentState?.loadChats();
  }

  setState(() {
    _currentIndex = index;
  });
}

  void _showAccountSwitcher(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
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
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ..._memberVenues.map(
                  (venue) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.storefront, color: colors.primary),
                    ),
                    title: Text(
                      venue.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    trailing: _activeAccount == venue.name
                        ? Icon(Icons.check_circle, color: colors.primary)
                        : null,
                    onTap: () async {
                      Navigator.pop(context);
                      final rootContext = this.context;
                      try {
                        await _switchToVenue(venue);
                      } catch (_) {
                        if (!rootContext.mounted) return;
                        await showPremiumErrorDialog(
                          rootContext,
                          message: 'Could not switch to venue account.',
                        );
                      }
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.settings_outlined,
                    color: colors.onSurface,
                  ),
                  title: Text(
                    'Account Settings',
                    style: TextStyle(color: colors.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountSettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.person_outline, color: colors.onSurface),
                  title: Text(
                    _isVenueContext
                        ? (_hasPersonalProfile
                              ? 'Switch to $_personalAccountLabel'
                              : 'Create Personal Account')
                        : _personalAccountLabel,
                    style: TextStyle(color: colors.onSurface),
                  ),
                  trailing: !_isVenueContext
                      ? Icon(Icons.check_circle, color: colors.primary)
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!_isVenueContext) {
                      return;
                    }
                    final rootContext = this.context;
                    try {
                      await _switchToPersonal();
                    } catch (_) {
                      if (!rootContext.mounted) return;
                      await showPremiumErrorDialog(
                        rootContext,
                        message: 'Could not switch to personal account.',
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: colors.error),
                  title: Text(
                    'Log out',
                    style: TextStyle(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    final rootContext = this.context;
                    Navigator.pop(context);
                    await _logout(rootContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pages = _isVenueContext
        ? <Widget>[
            const VenueAccountHomePage(),
            const NotificationPage(),
            VenueProfilePage(
              activeVenueName: _activeAccount == 'Personal'
                  ? null
                  : _activeAccount,
              venueNames: _memberVenues.map((v) => v.name).toList(),
            ),
          ]
        : <Widget>[
            const VenueHomePage(),
            const NotificationPage(),
            DmListPage(key: _dmListKey),
            const PeoplePage(),
            const ProfilePage(),
          ];
    final safeIndex = _currentIndex >= pages.length
        ? pages.length - 1
        : _currentIndex;

    return NotificationUnreadScope(
      unreadCount: _unreadNotificationCount,
      updateUnreadCount: (count) {
        if (_unreadNotificationCount != count) {
          setState(() => _unreadNotificationCount = count);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: pages[safeIndex],
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: isDark
              ? theme.colorScheme.surface.withValues(alpha: 0.95)
              : theme.colorScheme.surface.withValues(alpha: 0.95),
          elevation: 0,
          currentIndex: safeIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: theme.colorScheme.primary,
          unselectedItemColor: isDark ? Colors.white24 : Colors.grey.shade400,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          onTap: _onItemTapped,
          items: _isVenueContext
              ? [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined, size: 30),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: _buildNotificationIcon(),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: GestureDetector(
                      onLongPress: () {
                        _showAccountSwitcher(context);
                      },
                      child: _buildProfileAvatar(
                        isActive: safeIndex == 4,
                        isDark: isDark,
                        theme: theme,
                      ),
                    ),
                    label: '',
                  ),
                ]
              : [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined, size: 30),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: _buildNotificationIcon(),
                    label: '',
                  ),
                  const BottomNavigationBarItem(
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
                    icon: GestureDetector(
                      onLongPress: () {
                        _showAccountSwitcher(context);
                      },
                      child: _buildProfileAvatar(
                        isActive: safeIndex == 2,
                        isDark: isDark,
                        theme: theme,
                      ),
                    ),
                    label: '',
                  ),
                ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar({
    required bool isActive,
    required bool isDark,
    required ThemeData theme,
  }) {
    final colors = theme.colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? colors.onSurface : Colors.transparent,
          width: 2,
        ),
        color: isDark
            ? colors.primary.withValues(alpha: 0.2)
            : colors.primary.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        _userInitial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: isDark ? colors.primary : colors.onSurface,
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
              color: AppTheme.brandCta,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _unreadNotificationCount > 99
                  ? '99+'
                  : '$_unreadNotificationCount',
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
