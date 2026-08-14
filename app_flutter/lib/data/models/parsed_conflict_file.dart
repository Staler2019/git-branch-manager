/// Mirrors `gbm::ConflictSegmentKind` (src/core/git/ConflictMarkerParser.h).
enum ConflictSegmentKind {
  text(0),
  region(1);

  const ConflictSegmentKind(this.value);

  final int value;

  static ConflictSegmentKind fromValue(int value) =>
      ConflictSegmentKind.values.firstWhere(
        (k) => k.value == value,
        orElse: () => ConflictSegmentKind.text,
      );
}

/// Mirrors `gbm::ConflictSegment`. One stretch of a conflict-marked file:
/// either plain text carried through unchanged ([kind] == [ConflictSegmentKind.text],
/// only [lines] populated), or one `<<<<<<</=======/>>>>>>>` conflict region
/// ([kind] == [ConflictSegmentKind.region], [ours]/[theirs]/[base]
/// populated instead). Each line string keeps its own trailing line ending
/// ("foo\n" or "foo\r\n"; a file's last line has none if the file itself
/// has no trailing newline), so re-assembly (see conflict_resolve_logic.dart's
/// `assembleConflictResolution`) is pure concatenation.
class ConflictSegment {
  const ConflictSegment({
    required this.kind,
    required this.lines,
    required this.ours,
    required this.theirs,
    required this.base,
    required this.hasBase,
  });

  factory ConflictSegment.fromJson(Map<String, dynamic> json) {
    return ConflictSegment(
      kind: ConflictSegmentKind.fromValue(json['kind'] as int),
      lines: (json['lines'] as List<dynamic>).cast<String>(),
      ours: (json['ours'] as List<dynamic>).cast<String>(),
      theirs: (json['theirs'] as List<dynamic>).cast<String>(),
      base: (json['base'] as List<dynamic>).cast<String>(),
      hasBase: json['hasBase'] as bool,
    );
  }

  final ConflictSegmentKind kind;
  final List<String> lines;
  final List<String> ours;
  final List<String> theirs;
  final List<String> base;
  final bool hasBase;
}

/// Mirrors `gbm::ParsedConflictFile` as serialized by
/// `capi::toJson(const ParsedConflictFile&)`.
class ParsedConflictFile {
  const ParsedConflictFile({
    required this.segments,
    required this.regionCount,
    required this.wellFormed,
  });

  factory ParsedConflictFile.fromJson(Map<String, dynamic> json) {
    return ParsedConflictFile(
      segments: (json['segments'] as List<dynamic>)
          .map((e) => ConflictSegment.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      regionCount: json['regionCount'] as int,
      wellFormed: json['wellFormed'] as bool,
    );
  }

  static const ParsedConflictFile empty = ParsedConflictFile(
    segments: <ConflictSegment>[],
    regionCount: 0,
    wellFormed: true,
  );

  final List<ConflictSegment> segments;
  final int regionCount;
  final bool wellFormed;

  /// The [ConflictSegmentKind.region] segments only, in file order --
  /// index-aligned with a caller's per-region resolution list.
  List<ConflictSegment> get regions => segments
      .where((s) => s.kind == ConflictSegmentKind.region)
      .toList(growable: false);
}
