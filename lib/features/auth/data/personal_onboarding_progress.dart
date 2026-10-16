/// A profile row is created on the first save, not on completion. Use the
/// persisted step AND required fields at every personal entry point.
String? personalOnboardingStep(Map<String, dynamic> me) {
  String value(String key, [String? alias]) =>
      (me[key] ?? (alias == null ? null : me[alias]))?.toString().trim() ?? '';
  if (value('username', 'user_name').isEmpty) return 'USERNAME';
  if (value('fullName', 'full_name').isEmpty ||
      DateTime.tryParse(value('birthdate')) == null) {
    return 'NAME_DOB';
  }
  final step = value('onboardingStep', 'onboarding_step').toUpperCase();
  if (step == 'BIO' || step == 'NAME_DOB') return 'BIO';
  if (value('gender').isEmpty ||
      value('interestedIn', 'interested_in').isEmpty) {
    return 'GENDER_INTEREST';
  }
  if (step == 'GENDER_INTEREST' || step == 'PHOTO') return 'PHOTO';
  if (step == 'PERMISSIONS') return 'PERMISSIONS';
  return null;
}
