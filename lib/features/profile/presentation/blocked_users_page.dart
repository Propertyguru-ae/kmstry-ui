import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final MatchRepository _repo = MatchRepository();
  final Set<String> _unblockingUserIds = <String>{};
  bool _loading = true;
  List<BlockedUser> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _loading = true);
    try {
      final blocked = await _repo.getBlockedUsers();
      if (!mounted) return;
      setState(() {
        _blockedUsers = blocked;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    if (_unblockingUserIds.contains(user.userId)) return;
    setState(() => _unblockingUserIds.add(user.userId));
    try {
      await _repo.unblockUser(user.userId);
      if (!mounted) return;
      setState(() {
        _blockedUsers.removeWhere((u) => u.userId == user.userId);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not unblock user.')),
      );
    } finally {
      if (mounted) {
        setState(() => _unblockingUserIds.remove(user.userId));
      }
    }
  }

  void _openProfile(BlockedUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          userId: user.userId,
          userName: user.fullName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked users'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _blockedUsers.isEmpty
          ? Center(
              child: Text(
                'No blocked users',
                style: TextStyle(color: colors.onSurface),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadBlockedUsers,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _blockedUsers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final user = _blockedUsers[index];
                  final unblocking = _unblockingUserIds.contains(user.userId);
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: colors.surface,
                    title: Text(
                      user.fullName,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _openProfile(user),
                    trailing: TextButton(
                      onPressed: unblocking ? null : () => _unblock(user),
                      child: Text(unblocking ? '...' : 'Unblock'),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
