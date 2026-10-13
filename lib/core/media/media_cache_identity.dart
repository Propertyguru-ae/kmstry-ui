/// Signed query rotation is not a new photo; replacing the object path is.
String mediaObjectIdentity(String url) {
  final uri = Uri.tryParse(url);
  return uri == null ? url : uri.replace(query: '', fragment: '').toString();
}

String? mediaCacheIdentity(String url, {String? mediaId}) {
  final id = mediaId?.trim();
  if (id != null && id.isNotEmpty) {
    if (id.endsWith(':profile') || id.endsWith(':venue-photo')) {
      return '$id:${mediaObjectIdentity(url)}';
    }
    return id;
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (!uri.queryParameters.containsKey('X-Amz-Signature') &&
          !uri.queryParameters.containsKey('x-amz-signature'))) {
    return null;
  }
  return mediaObjectIdentity(url);
}
