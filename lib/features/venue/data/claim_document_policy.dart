/// Private ownership evidence is separate from public media sharing. Keep this
/// aligned with the backend claim-document-policy; no environment override.
abstract final class ClaimDocumentPolicy {
  static const ownershipVideoEnabled = false;
  static const requiredDocumentCount = ownershipVideoEnabled ? 2 : 1;

  static bool hasRequiredDocuments(String? licence, [String? video]) =>
      licence != null &&
      licence.trim().isNotEmpty &&
      (!ownershipVideoEnabled || (video != null && video.trim().isNotEmpty));
}
