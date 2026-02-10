import 'package:flutter/material.dart';

/// Provides unread notification count and update callback for navbar badge.
/// AppShell provides this; NotificationPage calls updateUnreadCount after fetch/mark read.
class NotificationUnreadScope extends InheritedWidget {
  const NotificationUnreadScope({
    super.key,
    required this.unreadCount,
    required this.updateUnreadCount,
    required super.child,
  });

  final int unreadCount;
  final void Function(int) updateUnreadCount;

  static NotificationUnreadScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NotificationUnreadScope>();
  }

  @override
  bool updateShouldNotify(NotificationUnreadScope oldWidget) {
    return oldWidget.unreadCount != unreadCount;
  }
}
