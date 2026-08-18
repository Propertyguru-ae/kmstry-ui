import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/bio_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/gender_interest_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/photo_onboarding_page.dart';

/// Kişisel onboarding adımları: username → name/DOB → bio → gender → photo.
enum OnboardingFlowStep { username, nameDob, bio, gender, photo }

/// Kişisel onboarding'i **tek bir lineer stack** içinde barındıran host.
///
/// Her adım kendi iç [Navigator]'ında yaşar; ileri gitmek adımın `onContinue`
/// kancasıyla bir sonraki adımı push eder, geri gitmek iç navigator'ı pop eder
/// (adım sayfalarındaki mevcut `canPop` tabanlı geri tuşu otomatik çalışır).
/// Böylece kullanıcı username↔name↔bio↔gender arasında doğal biçimde gidip
/// gelebilir ve önceki adımları düzenleyebilir. Son adım tamamlanınca akış
/// köke (authGate) döner ve kalan adımlar (permissions/home) oradan devam eder.
///
/// [startAt] devam (resume) noktası: authGate hangi adımın ilk tamamlanmamış
/// adım olduğunu hesaplar; ondan önceki adımlar geri gidilebilir olarak
/// stack'e seed edilir.
class PersonalOnboardingFlow extends StatefulWidget {
  final OnboardingFlowStep startAt;
  final String? initialUsername;
  final String? initialName;
  final DateTime? initialBirthdate;
  final bool nameReadOnly;
  final String? initialBio;

  /// "Maybe later" — venue kullanıcısı personal eklerken vazgeçerse. Null ise
  /// gizlenir (yeni kayıtta username zorunlu).
  final VoidCallback? onCancel;

  const PersonalOnboardingFlow({
    super.key,
    required this.startAt,
    this.initialUsername,
    this.initialName,
    this.initialBirthdate,
    this.nameReadOnly = false,
    this.initialBio,
    this.onCancel,
  });

  @override
  State<PersonalOnboardingFlow> createState() => _PersonalOnboardingFlowState();
}

class _PersonalOnboardingFlowState extends State<PersonalOnboardingFlow> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  static const _order = [
    OnboardingFlowStep.username,
    OnboardingFlowStep.nameDob,
    OnboardingFlowStep.bio,
    OnboardingFlowStep.gender,
    OnboardingFlowStep.photo,
  ];

  /// Görünür adım stack'i (adım indeksleri). İlk tamamlanmamış adıma kadar olan
  /// tüm adımlar seed edilir ki geri gidilebilsin.
  late List<int> _stack;
  late String? _draftName;
  late DateTime? _draftBirthdate;

  int get _startIndex => _order.indexOf(widget.startAt);

  @override
  void initState() {
    super.initState();
    final start = _startIndex < 0 ? 0 : _startIndex;
    _stack = [for (int i = 0; i <= start; i++) i];
    _draftName = widget.initialName;
    _draftBirthdate = widget.initialBirthdate;
  }

  @override
  Widget build(BuildContext context) {
    final flow = PopScope(
      // Host route asla pop edilmez; sistem geri tuşu yalnızca iç navigator'ı
      // (adımlar arası) pop eder. İlk adımdayken hiçbir şey olmaz.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _navKey.currentState?.maybePop();
      },
      child: Navigator(
        key: _navKey,
        pages: [
          for (final i in _stack)
            MaterialPage(key: ValueKey('onb_step_$i'), child: _buildStep(i)),
        ],
        onDidRemovePage: (page) {
          // İster sayfanın kendi geri tuşu, ister sistem geri tuşu olsun; pop
          // edilen sayfayı stack'ten çıkararak deklaratif listeyi eşitle.
          if (_stack.isEmpty) return;
          if (page.key == ValueKey('onb_step_${_stack.last}')) {
            setState(() => _stack.removeLast());
          }
        },
      ),
    );

    // İlk kayıt (onCancel == null) → marka akışı, DAİMA dark.
    // Add-personal (venue kullanıcısı sonradan ekliyor, onCancel != null) →
    // kullanıcının seçtiği temayı izler.
    return widget.onCancel == null ? ForceDark(child: flow) : flow;
  }

  /// Kaydetme sonrası ilerleme: sonraki adımı stack'e ekle, son adımsa bitir.
  void _advance(int index) {
    if (index < _order.length - 1) {
      setState(() => _stack.add(index + 1));
    } else {
      _finish();
    }
  }

  /// Akışı bitir: köke (authGate) dön, kalan adımlar oradan devam etsin.
  void _finish() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacementNamed(AuthRoutes.authGate);
  }

  Widget _buildStep(int index) {
    final step = _order[index];
    switch (step) {
      case OnboardingFlowStep.username:
        return UsernameOnboardingPage(
          initialUsername: widget.initialUsername,
          onCancel: widget.onCancel,
          onContinue: () => _advance(index),
        );
      case OnboardingFlowStep.nameDob:
        return NameDobOnboardingPage(
          initialName: _draftName,
          initialBirthdate: _draftBirthdate,
          nameReadOnly: widget.nameReadOnly,
          onCancel: widget.onCancel,
          onSaved: (fullName, birthdate) {
            _draftName = fullName;
            _draftBirthdate = birthdate;
          },
          onContinue: () => _advance(index),
        );
      case OnboardingFlowStep.bio:
        return BioOnboardingPage(
          initialBio: widget.initialBio,
          onContinue: () => _advance(index),
        );
      case OnboardingFlowStep.gender:
        return GenderInterestOnboardingPage(onContinue: () => _advance(index));
      case OnboardingFlowStep.photo:
        return PhotoOnboardingPage(onContinue: () => _advance(index));
    }
  }
}
