import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

/// Profilden bio düzenleme. Ürün metinleri İngilizce.
class EditBioPage extends StatefulWidget {
  final String? initialBio;

  const EditBioPage({super.key, this.initialBio});

  static const int maxLength = 150;

  @override
  State<EditBioPage> createState() => _EditBioPageState();
}

class _EditBioPageState extends State<EditBioPage> {
  late final TextEditingController _controller;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBio ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.characters.length > EditBioPage.maxLength) return;

    setState(() => _loading = true);
    try {
      await AuthRepository().updateMe({'bio': text});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showPremiumErrorDialog(context, message: 'Could not save bio');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final len = _controller.text.characters.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Bio'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This text appears on your profile and as the default for your check-in vibe.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                maxLines: 5,
                maxLength: EditBioPage.maxLength,
                decoration: InputDecoration(
                  hintText: 'Say something about yourself…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (len > EditBioPage.maxLength)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Bio is too long.',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed:
                    _loading || len > EditBioPage.maxLength ? null : _save,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
