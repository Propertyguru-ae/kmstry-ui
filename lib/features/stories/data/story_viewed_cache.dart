import 'package:shared_preferences/shared_preferences.dart';

/// Görüntülenmiş story ID'lerini cihazda kalıcı olarak saklar.
/// Story viewer her story'i açtığında buraya yazar; tray halkasını
/// buna göre renkli/gri yapar.
class StoryViewedCache {
  static const _key = 'viewed_story_ids';

  /// Bu story'nin görüldüğünü işaretle.
  static Future<void> markViewed(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    if (!ids.contains(storyId)) {
      ids.add(storyId);
      // En fazla 500 ID tut (en eskiyi at) — hafıza şişmesin.
      if (ids.length > 500) ids.removeRange(0, ids.length - 500);
      await prefs.setStringList(_key, ids);
    }
  }

  /// Verilen ID'lerin TÜMÜnü görüp görmediğini döner.
  static Future<bool> allViewed(List<String> storyIds) async {
    if (storyIds.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    return storyIds.every((id) => ids.contains(id));
  }

  /// Senkron kontrol — prefs önceden yüklendiyse kullan.
  static bool allViewedSync(List<String> storyIds, Set<String> viewedIds) {
    if (storyIds.isEmpty) return true;
    return storyIds.every((id) => viewedIds.contains(id));
  }

  /// Tüm görülen ID'leri yükle (tray init'te bir kez çağrılır).
  static Future<Set<String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }
}
