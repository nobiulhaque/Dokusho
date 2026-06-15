/// Centralized syncId constants for all supported tracker providers.
/// These IDs are used as database keys in Isar (TrackPreference.syncId).
class TrackerProviders {
  static const TrackerInfo myAnimeList = TrackerInfo(syncId: 1);
  static const TrackerInfo anilist = TrackerInfo(syncId: 2);
  static const TrackerInfo kitsu = TrackerInfo(syncId: 3);
  static const TrackerInfo simkl = TrackerInfo(syncId: 4);
  static const TrackerInfo trakt = TrackerInfo(syncId: 5);
}

class TrackerInfo {
  final int syncId;
  const TrackerInfo({required this.syncId});
}
