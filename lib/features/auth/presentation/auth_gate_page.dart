import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/login_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/legal_update_required_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/context_choice_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/permissions_flow_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/personal_onboarding_flow.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_pending_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_member_invite_page.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    try {
      final isLoggedIn = await AuthRepository().restoreSession();
      if (!mounted) return;

      if (!isLoggedIn) {
        _go(const LoginPage());
        return;
      }

      final me = await AuthRepository().getMe(forceRefresh: true);
      if (_legalConsentRequired(me)) {
        _logDecision('legal_consent_required');
        _go(const LegalUpdateRequiredPage());
        return;
      }
      final meContext = MeContextModel.fromMe(me);
      final homeRoute = meContext.homeRoute?.toUpperCase();
      final nextAction = meContext.nextAction?.toUpperCase();
      final lastActiveContext = meContext.lastActiveContext?.toUpperCase();
      final hasVenueContext =
          meContext.hasVenueMembership || meContext.memberVenues.isNotEmpty;
      final fullName =
          (me['fullName'] ?? me['full_name'])?.toString().trim() ?? '';
      final birthdate = me['birthdate']?.toString().trim() ?? '';
      final gender = me['gender']?.toString().trim() ?? '';
      final username =
          (me['username'] ?? me['user_name'])?.toString().trim() ?? '';
      final interestedIn =
          (me['interestedIn'] ?? me['interested_in'])?.toString().trim() ?? '';
      final onboardingStep = (me['onboardingStep'] ?? me['onboarding_step'])
          ?.toString()
          .toUpperCase();
      debugPrint(
        '[AuthGate] homeRoute=$homeRoute nextAction=$nextAction lastActiveContext=$lastActiveContext hasVenueMembership=${meContext.hasVenueMembership} memberVenues=${meContext.memberVenues.length}',
      );
      final devicePermissionsDone =
          await SecureStorage.isDevicePermissionsOnboardingDone();
      final hasNameDob = fullName.isNotEmpty && birthdate.isNotEmpty;
      final hasUsername = username.isNotEmpty;
      final hasGenderInterest = gender.isNotEmpty && interestedIn.isNotEmpty;
      final hasInferredPersonalProfile =
          fullName.isNotEmpty &&
          birthdate.isNotEmpty &&
          gender.isNotEmpty &&
          interestedIn.isNotEmpty;
      final hasPersonalProfile =
          meContext.hasPersonalProfile || hasInferredPersonalProfile;
      String? resolvedVenueId = meContext.activeVenueId;
      if (resolvedVenueId == null ||
          resolvedVenueId.isEmpty ||
          !meContext.memberVenues.any((venue) => venue.id == resolvedVenueId)) {
        resolvedVenueId = meContext.memberVenues.isNotEmpty
            ? meContext.memberVenues.first.id
            : null;
      }
      _lastResolvedVenueId = resolvedVenueId;
      debugPrint(
        '[AuthGate2] hasPersonalProfile=$hasPersonalProfile hasInferredPersonalProfile=$hasInferredPersonalProfile onboardingStep=$onboardingStep resolvedVenueId=$resolvedVenueId',
      );

      // Venue üyeliği varsa personal onboarding sayfalarında "Maybe later" çalışsın.
      final onCancelPersonal = _makeCancelCallback(
        meContext.hasVenueMembership,
        resolvedVenueId,
      );

      // On fresh installs, existing accounts can come with COMPLETED but still need
      // device permission onboarding on this device.
      if (onboardingStep == 'COMPLETED' && !devicePermissionsDone) {
        _logDecision('completed_but_device_permissions_missing');
        _go(PermissionsFlowPage(markProfileCompleted: false, forceDark: false));
        return;
      }

      // Venue claim reddedilmiş → venue home'a yönlendir; banner orada gösterilir.
      if (nextAction == 'VENUE_CLAIM_REJECTED' ||
          meContext.hasRejectedClaimOnly) {
        _logDecision('venue_claim_rejected_go_venue_home');
        final rejectedVenue = meContext.memberVenues
            .where((v) => v.isRejectedOwnerClaim)
            .firstOrNull;
        if (rejectedVenue != null) {
          _lastResolvedVenueId = rejectedVenue.id;
          await _applyVenueContextIfNeeded(rejectedVenue.id);
        }
        await _routeToVenueHome();
        return;
      }

      // Safe fallback for known backend inconsistency:
      // venue-only users occasionally receive PERSONAL_ONBOARDING.
      final isConflictingVenueOnlyPayload =
          hasVenueContext &&
          !hasPersonalProfile &&
          !meContext
              .hasRejectedClaimOnly && // rejected claim kullanıcısı buraya düşmemeli
          (homeRoute == 'PERSONAL_ONBOARDING' ||
              nextAction == 'START_PERSONAL_ONBOARDING');
      if (isConflictingVenueOnlyPayload) {
        _logDecision('safe_fallback_venue_only_payload');
        await _applyVenueContextIfNeeded(resolvedVenueId);
        await _routeToVenueHome();
        return;
      }

      // Safe fallback: backend sends VENUE_ONBOARDING but user already has
      // an active venue membership — skip onboarding and go to venue home.
      final isConflictingVenueOnboardingPayload =
          hasVenueContext &&
          (homeRoute == 'VENUE_ONBOARDING' ||
              nextAction == 'START_VENUE_ONBOARDING');
      if (isConflictingVenueOnboardingPayload) {
        _logDecision('safe_fallback_venue_onboarding_but_has_membership');
        await _applyVenueContextIfNeeded(resolvedVenueId);
        await _routeToVenueHome();
        return;
      }

      // Safe fallback: some mixed accounts can incorrectly come back as VENUE_HOME
      // even when personal profile fields are present. In that case we open personal
      // first, and user can switch back to venue from the account switcher.
      if (hasVenueContext &&
          hasInferredPersonalProfile &&
          lastActiveContext == 'PERSONAL' &&
          nextAction != 'AWAIT_VENUE_APPROVAL' &&
          (homeRoute == 'VENUE_HOME' || nextAction == 'GO_TO_VENUE_HOME')) {
        _logDecision('safe_fallback_mixed_account_prefers_personal');
        await _routeToPersonalHome();
        return;
      }

      // 1) Authoritative server routes first.
      if (homeRoute == 'VENUE_HOME' || nextAction == 'GO_TO_VENUE_HOME') {
        _logDecision('server_route_venue_home');
        await _applyVenueContextIfNeeded(resolvedVenueId);
        await _routeToVenueHome();
        return;
      }
      if (homeRoute == 'PERSONAL_HOME' || nextAction == 'GO_TO_PERSONAL_HOME') {
        // For personal context, onboarding step still has priority.
        if (!hasUsername) {
          _logDecision('personal_home_step_username');
          _goPersonalOnboarding(
            OnboardingFlowStep.username,
            me,
            onCancelPersonal,
          );
          return;
        }
        if (onboardingStep == 'NAME_DOB' && !hasNameDob) {
          _logDecision('personal_home_step_name_dob');
          _goPersonalOnboarding(
            OnboardingFlowStep.nameDob,
            me,
            onCancelPersonal,
          );
          return;
        }
        if (onboardingStep == 'BIO') {
          if (!hasNameDob) {
            _logDecision('personal_home_bio_requires_name_dob');
            _goPersonalOnboarding(
              OnboardingFlowStep.nameDob,
              me,
              onCancelPersonal,
            );
            return;
          }
          _logDecision('personal_home_step_bio');
          _goPersonalOnboarding(OnboardingFlowStep.bio, me, onCancelPersonal);
          return;
        }
        if (onboardingStep == 'GENDER_INTEREST') {
          if (!hasGenderInterest) {
            _logDecision('personal_home_step_gender_interest');
            _goPersonalOnboarding(
              OnboardingFlowStep.gender,
              me,
              onCancelPersonal,
            );
            return;
          }
          // Gender+interest already set but step not yet advanced → go to permissions
          _logDecision(
            'personal_home_step_gender_interest_completed_go_permissions',
          );
          _go(PermissionsFlowPage(forceDark: onCancelPersonal == null));
          return;
        }
        if (onboardingStep == 'PHOTO') {
          _logDecision('personal_home_step_photo');
          _goPersonalOnboarding(OnboardingFlowStep.photo, me, onCancelPersonal);
          return;
        }
        if (onboardingStep == 'PERMISSIONS') {
          _logDecision('personal_home_step_permissions');
          _go(PermissionsFlowPage(forceDark: onCancelPersonal == null));
          return;
        }
        _logDecision('server_route_personal_home');
        await _routeToPersonalHome();
        return;
      }
      if (homeRoute == 'CONTEXT_CHOICE' ||
          nextAction == 'SHOW_CONTEXT_CHOICE') {
        // Eğer tamamlanmamış venue claim draft'ı varsa → wizard'a yönlendir, PERSONAL'a basma.
        // Ama kullanıcının bekleyen bir üyelik daveti varsa claim wizard'ı gösterme;
        // davet bildirimler sayfasından erişilebilir.
        final hasClaimDraft = me['hasClaimDraft'] == true;
        final hasPendingMemberInvite = meContext.memberVenues.any(
          (v) => v.isPendingMemberInvite,
        );
        if (hasClaimDraft && !hasPendingMemberInvite) {
          _logDecision('context_choice_has_claim_draft_venue_onboarding');
          _go(const VenueContextOnboardingPage());
          return;
        }

        _logDecision('server_route_context_choice_show_choice');
        _go(const ContextChoicePage(isAuthenticated: true));
        return;
      }
      if (homeRoute == 'VENUE_MEMBER_INVITE' ||
          nextAction == 'SHOW_VENUE_MEMBER_INVITE') {
        _logDecision('server_route_venue_member_invite');
        final pendingInvites = meContext.memberVenues
            .where((v) => v.isPendingMemberInvite)
            .toList();
        _go(VenueMemberInvitePage(pendingInvites: pendingInvites));
        return;
      }
      if (homeRoute == 'VENUE_PENDING_DOCS') {
        _logDecision('server_route_venue_pending_docs');
        _go(const VenuePendingPage(mode: VenuePendingMode.pendingDocs));
        return;
      }
      if (homeRoute == 'VENUE_PENDING' ||
          nextAction == 'AWAIT_VENUE_APPROVAL') {
        _logDecision('server_route_venue_pending');
        _go(const VenuePendingPage());
        return;
      }
      if (homeRoute == 'VENUE_ONBOARDING' ||
          nextAction == 'START_VENUE_ONBOARDING') {
        _logDecision('server_route_venue_onboarding');
        _go(const VenueContextOnboardingPage());
        return;
      }
      if (homeRoute == 'PERSONAL_ONBOARDING' ||
          nextAction == 'START_PERSONAL_ONBOARDING') {
        if (!hasUsername) {
          _logDecision('server_route_personal_onboarding_username');
          _goPersonalOnboarding(
            OnboardingFlowStep.username,
            me,
            onCancelPersonal,
          );
          return;
        }
        if (onboardingStep == 'NAME_DOB' && !hasNameDob) {
          _logDecision('server_route_personal_onboarding_name_dob');
          _goPersonalOnboarding(
            OnboardingFlowStep.nameDob,
            me,
            onCancelPersonal,
          );
          return;
        }
        if (onboardingStep == 'BIO') {
          if (!hasNameDob) {
            _logDecision(
              'server_route_personal_onboarding_bio_requires_name_dob',
            );
            _goPersonalOnboarding(
              OnboardingFlowStep.nameDob,
              me,
              onCancelPersonal,
            );
            return;
          }
          _logDecision('server_route_personal_onboarding_bio');
          _goPersonalOnboarding(OnboardingFlowStep.bio, me, onCancelPersonal);
          return;
        }
        if (onboardingStep == 'GENDER_INTEREST') {
          if (!hasGenderInterest) {
            _logDecision('server_route_personal_onboarding_gender_interest');
            _goPersonalOnboarding(
              OnboardingFlowStep.gender,
              me,
              onCancelPersonal,
            );
            return;
          }
          // Gender+interest already set but step not yet advanced → go to permissions
          _logDecision(
            'server_route_personal_onboarding_gender_interest_completed_go_permissions',
          );
          _go(PermissionsFlowPage(forceDark: onCancelPersonal == null));
          return;
        }
        if (onboardingStep == 'PHOTO') {
          _logDecision('server_route_personal_onboarding_photo');
          _goPersonalOnboarding(OnboardingFlowStep.photo, me, onCancelPersonal);
          return;
        }
        if (onboardingStep == 'PERMISSIONS') {
          _logDecision('server_route_personal_onboarding_permissions');
          _go(PermissionsFlowPage(forceDark: onCancelPersonal == null));
          return;
        }
        if (onboardingStep == 'COMPLETED') {
          _logDecision('server_route_personal_onboarding_completed');
          await _routeToPersonalHome();
          return;
        }
        if (!hasPersonalProfile && hasNameDob) {
          _logDecision(
            'server_route_personal_onboarding_inferred_gender_interest',
          );
          _goPersonalOnboarding(
            OnboardingFlowStep.gender,
            me,
            onCancelPersonal,
          );
          return;
        }
        if (!hasPersonalProfile) {
          _logDecision('server_route_personal_onboarding');
          _goPersonalOnboarding(
            OnboardingFlowStep.nameDob,
            me,
            onCancelPersonal,
          );
          return;
        }
        _logDecision('server_route_personal_onboarding_but_profile_exists');
        await _routeToPersonalHome();
        return;
      }

      // 2) Fallback by last active context.
      if (lastActiveContext == 'VENUE' && hasVenueContext) {
        _logDecision('fallback_last_context_venue');
        await _applyVenueContextIfNeeded(resolvedVenueId);
        await _routeToVenueHome();
        return;
      }
      if (lastActiveContext == 'PERSONAL' && hasPersonalProfile) {
        _logDecision('fallback_last_context_personal');
        await _routeToPersonalHome();
        return;
      }

      // 3) Fallback by profile/membership presence.
      if (hasVenueContext && !hasPersonalProfile) {
        _logDecision('fallback_venue_only');
        await _applyVenueContextIfNeeded(resolvedVenueId);
        await _routeToVenueHome();
        return;
      }
      if (!hasVenueContext && hasPersonalProfile) {
        _logDecision('fallback_personal_only');
        await _routeToPersonalHome();
        return;
      }

      final step = me['onboardingStep'] ?? me['onboarding_step'];

      // 4) Legacy onboarding_step is the last fallback.
      switch (step) {
        case 'NAME_DOB':
          if (!hasUsername) {
            _logDecision('legacy_username_before_name_dob');
            _goPersonalOnboarding(
              OnboardingFlowStep.username,
              me,
              onCancelPersonal,
            );
            return;
          }
          _logDecision('legacy_name_dob');
          _goPersonalOnboarding(
            OnboardingFlowStep.nameDob,
            me,
            onCancelPersonal,
          );
          return;

        case 'BIO':
          if (!hasUsername) {
            _logDecision('legacy_username_before_bio');
            _goPersonalOnboarding(
              OnboardingFlowStep.username,
              me,
              onCancelPersonal,
            );
            return;
          }
          if (!hasNameDob) {
            _logDecision('legacy_bio_requires_name_dob');
            _goPersonalOnboarding(
              OnboardingFlowStep.nameDob,
              me,
              onCancelPersonal,
            );
            return;
          }
          _logDecision('legacy_bio');
          _goPersonalOnboarding(OnboardingFlowStep.bio, me, onCancelPersonal);
          return;

        case 'GENDER_INTEREST':
          if (!hasGenderInterest) {
            _logDecision('legacy_gender_interest');
            _goPersonalOnboarding(
              OnboardingFlowStep.gender,
              me,
              onCancelPersonal,
            );
            return;
          }
          _logDecision('legacy_gender_interest_skip_already_completed');
          await _routeToPersonalHome();
          return;

        case 'PHOTO':
          _logDecision('legacy_photo');
          _goPersonalOnboarding(OnboardingFlowStep.photo, me, onCancelPersonal);
          return;

        case 'PERMISSIONS':
          _logDecision('legacy_permissions');
          _go(PermissionsFlowPage(forceDark: onCancelPersonal == null));
          return;

        case 'COMPLETED':
          _logDecision('legacy_completed');
          final devicePermissionsDone =
              await SecureStorage.isDevicePermissionsOnboardingDone();
          if (!devicePermissionsDone) {
            _go(PermissionsFlowPage(markProfileCompleted: false, forceDark: false));
            return;
          }
          await PushManager.instance.ensureRegisteredIfAllowed();
          _go(const AppShell());
          return;

        default:
          _logDecision('legacy_default');
          final devicePermissionsDone =
              await SecureStorage.isDevicePermissionsOnboardingDone();
          if (!devicePermissionsDone) {
            _go(PermissionsFlowPage(markProfileCompleted: false, forceDark: false));
            return;
          }
          await PushManager.instance.ensureRegisteredIfAllowed();
          // Güvenli fallback
          _go(const AppShell());
          return;
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[AuthGate] decision_error=$e');
      _go(const LoginPage());
    }
  }

  String? _namePrefill(Map<String, dynamic> me) {
    final name = (me['fullName'] ?? me['full_name'])?.toString().trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  DateTime? _birthdatePrefill(Map<String, dynamic> me) {
    final raw = me['birthdate']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String? _usernamePrefill(Map<String, dynamic> me) {
    final username = (me['username'] ?? me['user_name'])?.toString().trim();
    if (username == null || username.isEmpty) return null;
    return username;
  }

  String? _bioPrefill(Map<String, dynamic> me) {
    final raw = (me['bio'] ?? me['bio_text'])?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  bool _legalConsentRequired(Map<String, dynamic> me) {
    final direct = me['legalConsentRequired'] ?? me['legal_consent_required'];
    if (direct is bool) return direct;
    final legal = me['legalConsent'] ?? me['legal_consent'];
    if (legal is Map) {
      final required =
          legal['required'] ?? legal['isRequired'] ?? legal['is_required'];
      if (required is bool) return required;
    }
    return false;
  }

  void _logDecision(String branch) {
    debugPrint('[AuthGate] route_branch=$branch');
  }

  /// Venue üyeliği olan kullanıcı personal onboarding'i iptal ettiğinde:
  /// context'i VENUE'ya çevir ve authGate'e yönlendir.
  VoidCallback? _makeCancelCallback(
    bool hasVenueMembership,
    String? resolvedVenueId,
  ) {
    if (!hasVenueMembership) return null;
    return () async {
      try {
        await AuthRepository().switchContext(
          lastActiveContext: 'VENUE',
          activeVenueId: resolvedVenueId,
        );
      } catch (_) {}
      if (mounted) {
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      }
    };
  }

  Future<void> _applyVenueContextIfNeeded(String? venueId) async {
    if (venueId == null || venueId.isEmpty) return;
    try {
      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: venueId,
      );
    } catch (_) {}
  }

  String? _lastResolvedVenueId;

  Future<void> _routeToVenueHome() async {
    await PushManager.instance.ensureRegisteredIfAllowed();
    _go(
      AppShell(
        initialIndex: 0,
        initialIsVenueContext: true,
        initialVenueId: _lastResolvedVenueId,
      ),
    );
  }

  Future<void> _routeToPersonalHome() async {
    await PushManager.instance.ensureRegisteredIfAllowed();
    _go(const AppShell(initialIndex: 0));
  }

  void _go(Widget page) {
    // Remove every route beneath so no ghost personal/venue shell lingers
    // behind the transition and bleeds through.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  /// Kişisel onboarding adımlarını tek bir lineer akış (host) içinde açar; böylece
  /// kullanıcı adımlar arasında geri gidip düzenleyebilir. [step] devam noktası;
  /// ondan önceki adımlar geri gidilebilir olarak stack'e seed edilir.
  void _goPersonalOnboarding(
    OnboardingFlowStep step,
    Map<String, dynamic> me,
    VoidCallback? onCancel,
  ) {
    final name = _namePrefill(me);
    _go(
      PersonalOnboardingFlow(
        startAt: step,
        initialUsername: _usernamePrefill(me),
        initialName: name,
        initialBirthdate: _birthdatePrefill(me),
        nameReadOnly: false,
        initialBio: _bioPrefill(me),
        onCancel: onCancel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
