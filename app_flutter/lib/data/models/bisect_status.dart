/// Mirrors `gbm::BisectStatus` (src/core/git/ops/BisectOps.h) as serialized
/// by `capi::toJson(const BisectStatus&)`.
class BisectStatus {
  const BisectStatus({
    required this.active,
    required this.currentOid,
    required this.badOid,
    required this.goodOids,
    required this.skippedOids,
    required this.logText,
  });

  static const BisectStatus empty = BisectStatus(
    active: false,
    currentOid: '',
    badOid: '',
    goodOids: <String>[],
    skippedOids: <String>[],
    logText: '',
  );

  factory BisectStatus.fromJson(Map<String, dynamic> json) {
    return BisectStatus(
      active: json['active'] as bool,
      currentOid: json['currentOid'] as String,
      badOid: json['badOid'] as String,
      goodOids: (json['goodOids'] as List<dynamic>).cast<String>(),
      skippedOids: (json['skippedOids'] as List<dynamic>).cast<String>(),
      logText: json['logText'] as String,
    );
  }

  final bool active;
  final String currentOid;
  final String badOid;
  final List<String> goodOids;
  final List<String> skippedOids;
  final String logText;
}
