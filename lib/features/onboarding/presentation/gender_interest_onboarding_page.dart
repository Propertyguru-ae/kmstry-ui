import 'package:flutter/material.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class GenderInterestOnboardingPage extends StatefulWidget {
  const GenderInterestOnboardingPage({super.key});

  @override
  State<GenderInterestOnboardingPage> createState() =>
      _GenderInterestOnboardingPageState();
}

class _GenderInterestOnboardingPageState
    extends State<GenderInterestOnboardingPage> {
  String? gender;
  String? interest;
  bool loading = false;

  bool get valid => gender != null && interest != null;

  Future<void> submit() async {
    if (!valid) return;

    setState(() => loading = true);

    await AuthRepository().updateMe({
      'gender': gender,
      'interested_in': interest,
    });

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
  }

  Widget tile(
    String value,
    String label,
    String? selected,
    Function(String) onTap,
  ) {
    final active = selected == value;

    return GestureDetector(
      onTap: () => setState(() => onTap(value)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? Colors.black : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18))),
            if (active) const Icon(Icons.check),
          ],
        ),
      ),
    );
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
              'What’s your gender?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            tile('male', 'Male', gender, (v) => gender = v),
            const SizedBox(height: 8),
            tile('female', 'Female', gender, (v) => gender = v),

            const SizedBox(height: 24),
            const Text(
              'Who do you want to connect with?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            tile('men', 'Men', interest, (v) => interest = v),
            const SizedBox(height: 8),
            tile('women', 'Women', interest, (v) => interest = v),
            const SizedBox(height: 8),
            tile('everyone', 'Everyone', interest, (v) => interest = v),

            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: valid && !loading ? submit : null,
                child: loading
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
