import 'package:flutter/material.dart';
import '../data/aws_sharing_permission.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';

class AwsSharingPermissionTile extends StatefulWidget {
  const AwsSharingPermissionTile({super.key});
  @override
  State<AwsSharingPermissionTile> createState() =>
      _AwsSharingPermissionTileState();
}

class _AwsSharingPermissionTileState extends State<AwsSharingPermissionTile> {
  bool? _granted;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await AwsSharingPermission.instance.status();
      if (mounted) {
        setState(() {
          _granted = status['granted'] == true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load this choice. Tap to retry.');
      }
    }
  }

  Future<void> _change(bool value) async {
    if (_busy) return;
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Turn off AWS safety checks?'),
          content: const Text(
            'New public photos and text cannot be submitted. Unfinished uploads awaiting checks will be cancelled. This does not remove published content or recall information already sent. You can allow checks again whenever you are ready.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep on'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      if (value) {
        await AwsSharingPermission.instance.allow();
      } else {
        await AwsSharingPermission.instance.withdraw();
      }
    } catch (error) {
      if (error is! ApiException ||
          error.data['errorCode'] != 'AWS_SHARING_PERMISSION_DECLINED') {
        failure = 'The choice was not changed. Please try again.';
      }
    } finally {
      await _load();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure ?? _error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          title: const Text(
            'AWS safety checks',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Allow public photos and text to be checked by Amazon Web Services. Applies to your Personal and Venue activity on this account.',
          ),
          value: _granted ?? false,
          onChanged: _busy || _granted == null ? null : _change,
          secondary: _busy || (_granted == null && _error == null)
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.shield_outlined),
        ),
        if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
      ],
    ),
  );
}
