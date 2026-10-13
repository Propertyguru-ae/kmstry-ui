List<String> normalizeRequiredCheckinIntents(Iterable<String> values) {
  final normalized = values
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();

  if (normalized.isEmpty) {
    throw ArgumentError(
      'Select at least one reason for your check-in',
      'whatBringsYou',
    );
  }

  return normalized;
}
