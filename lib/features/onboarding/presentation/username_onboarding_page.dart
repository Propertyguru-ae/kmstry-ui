import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class UsernameOnboardingPage extends StatefulWidget {
  final String? initialUsername;

  const UsernameOnboardingPage({super.key, this.initialUsername});

  @override
  State<UsernameOnboardingPage> createState() => _UsernameOnboardingPageState();
}

class _UsernameOnboardingPageState extends State<UsernameOnboardingPage> {
  late final TextEditingController _usernameController;
  Timer? _suggestionDebounce;
  bool _loading = false;
  bool _loadingSuggestions = false;
  String? _error;
  String? _suggestionError;
  List<String> _suggestions = const [];

  static final RegExp _usernameRegex = RegExp(r'^[a-z0-9._]{3,30}$');

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.initialUsername?.toLowerCase().trim() ?? '',
    );
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  String get _normalizedUsername => _usernameController.text.trim().toLowerCase();

  bool get _isValid => _usernameRegex.hasMatch(_normalizedUsername);

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final code = error.data['errorCode']?.toString().toUpperCase();
      final message = _extractBackendMessage(error.data);
      if (code == 'USERNAME_ALREADY_IN_USE') {
        return 'This username is already taken. Try another one.';
      }
      if (error.statusCode == 409 &&
          message.toLowerCase().contains('username already in use')) {
        return 'This username is already taken. Try another one.';
      }
      if (message.isNotEmpty) return message;
    }
    return 'Could not save username. Please try again.';
  }

  String _extractBackendMessage(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first?.toString().trim() ?? '';
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Future<void> _continue() async {
    if (!_isValid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthRepository().upsertPersonalProfile({
        'username': _normalizedUsername,
      });
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  void _onUsernameChanged() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _suggestionError = null;
    });

    _suggestionDebounce?.cancel();
    final base = _normalizedUsername;
    if (base.length < 3) {
      setState(() {
        _loadingSuggestions = false;
        _suggestions = const [];
      });
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(base);
    });
  }

  Future<void> _loadSuggestions(String base) async {
    if (!mounted) return;
    setState(() {
      _loadingSuggestions = true;
      _suggestionError = null;
    });
    try {
      final result = await AuthRepository().getUsernameSuggestions(base);
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestions = result.where((v) => v != _normalizedUsername).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestions = const [];
        _suggestionError = 'Could not load suggestions.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose username'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create your username',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'This will be unique.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _onUsernameChanged(),
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'e.g. kmstry.user',
                border: OutlineInputBorder(),
                helperText: '3-30 chars, lowercase letters, numbers, . and _',
              ),
            ),
            if (_loadingSuggestions)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Suggestions',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestions
                    .map(
                      (s) => ActionChip(
                        label: Text('@$s'),
                        onPressed: () {
                          setState(() {
                            _usernameController.text = s;
                            _usernameController.selection =
                                TextSelection.collapsed(offset: s.length);
                            _error = null;
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            if (_suggestionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _suggestionError!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            if (_usernameController.text.isNotEmpty && !_isValid)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Invalid username format.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
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
