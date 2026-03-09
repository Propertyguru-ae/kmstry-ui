import 'package:flutter/material.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class NameDobOnboardingPage extends StatefulWidget {
  final String? initialName;

  const NameDobOnboardingPage({
    super.key,
    this.initialName,
  });

  @override
  State<NameDobOnboardingPage> createState() => _NameDobOnboardingPageState();
}

class _NameDobOnboardingPageState extends State<NameDobOnboardingPage> {
  late final TextEditingController _nameController;
  DateTime? _birthdate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  bool get _is18Plus {
    if (_birthdate == null) return false;
    final today = DateTime.now();
    final age = today.year - _birthdate!.year;
    return age >= 18;
  }

  bool get _isValid {
    return _nameController.text.trim().isNotEmpty && _is18Plus;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18),
    );

    if (picked != null) {
      setState(() => _birthdate = picked);
    }
  }

  Future<void> _continue() async {
    if (!_isValid) return;

    setState(() => _loading = true);

    try {
      await AuthRepository().upsertPersonalProfile({
        'fullName': _nameController.text.trim(),
        'birthdate': _birthdate!.toIso8601String(),
      });

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AuthRoutes.authGate,
      );
    } catch (_) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About you'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What should we call you?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 32),

            const Text(
              'Your date of birth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _birthdate == null
                      ? 'Select date'
                      : _birthdate!.toLocal().toString().split(' ')[0],
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            if (_birthdate != null && !_is18Plus)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'You must be at least 18 years old',
                  style: TextStyle(color: Colors.red),
                ),
              ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValid && !_loading ? _continue : null,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
