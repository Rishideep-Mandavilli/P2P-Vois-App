// Vois offline peer-to-peer radio communication module
/// Preset distress categories — sent as a tiny coded payload instead of a
/// spoken sentence, so an SOS gets through even when the link is too
/// degraded to carry audio.
enum SosCode {
  trapped,
  medical,
  fire,
  flood,
  needWater,
  safe;

  String get label => switch (this) {
        SosCode.trapped => 'Trapped',
        SosCode.medical => 'Medical',
        SosCode.fire => 'Fire',
        SosCode.flood => 'Flood',
        SosCode.needWater => 'Need Water',
        SosCode.safe => 'Safe',
      };

  /// Stable machine identifier put on the wire; [label] is display-only and
  /// localisable without breaking compatibility with older builds.
  String get code => name;

  static SosCode? fromCode(String code) {
    for (final c in SosCode.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}
