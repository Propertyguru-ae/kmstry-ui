class DailyUndoQuota {
  final int remaining;
  final DateTime resetsAt;
  const DailyUndoQuota(this.remaining, this.resetsAt);

  static DailyUndoQuota? fromResponse(Object? response) {
    final data = response is Map ? response['quota'] : null;
    if (data is! Map) return null;
    final count = data['remaining'];
    final end = data['resetsAt'];
    final resetsAt = end is String ? DateTime.tryParse(end) : null;
    if (count is! int || count < 0 || resetsAt == null) return null;
    return DailyUndoQuota(count, resetsAt);
  }
}
