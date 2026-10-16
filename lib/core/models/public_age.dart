/// Public API responses expose age only; never infer/store a birthday.
int? readPublicAge(Map<String, dynamic> json) {
  final value = json['age'];
  return value is num && value.isFinite && value >= 0 && value == value.toInt()
      ? value.toInt()
      : null;
}
