import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import '../../auth/data/auth_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await AuthRepository().getMe(); 
      setState(() {
        _user = me;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, AuthRoutes.profile);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔔 VERIFY BANNER
          if (_user != null && _user!['email_verified'] == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Please verify your email address',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await AuthRepository().resendVerifyEmail();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification email sent'),
                        ),
                      );
                    },
                    child: const Text('Resend'),
                  ),
                ],
              ),
            ),

          const Expanded(child: Center(child: Text('HOME CONTENT'))),
        ],
      ),
    );
  }
}
