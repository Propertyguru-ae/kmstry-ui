import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';

/// Bir kişinin üç nokta menüsü: profil, Friends ve mesajlarda aynı sıra ve renkler.
/// [onRemoveFriend] yalnızca kaldırılabilir bir arkadaşlık varken verilir.
Future<void> showUserActionsSheet(
  BuildContext context, {
  String? title,
  String? subtitle,
  VoidCallback? onRemoveFriend,
  required VoidCallback onReport,
  required VoidCallback onToggleBlock,
  bool isBlocked = false,
}) {
  const danger = Color(0xFFEF4444);
  return showAppSheet<void>(
    context,
    builder: (ctx) {
      Widget row(
        String label,
        IconData icon,
        Color color,
        VoidCallback action,
      ) => AppSheetRow(
        leading: AppSheetIconTile(icon: icon, color: color),
        title: label,
        onTap: () {
          Navigator.of(ctx).pop();
          action();
        },
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSheetHeader(title: title, subtitle: subtitle),
              AppSheetCard(
                children: [
                  if (onRemoveFriend != null)
                    row(
                      'Remove friend',
                      Icons.person_remove_outlined,
                      danger,
                      onRemoveFriend,
                    ),
                  row(
                    'Report',
                    Icons.flag_outlined,
                    AppColors.orange,
                    onReport,
                  ),
                  row(
                    isBlocked ? 'Unblock' : 'Block',
                    Icons.block_rounded,
                    isBlocked ? AppColors.teal : danger,
                    onToggleBlock,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
