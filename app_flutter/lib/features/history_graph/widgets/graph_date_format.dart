/// Formats commit dates with mixed relative/absolute format.
///
/// Rule: relative for <24h, absolute date for >=1 day, year suffix when
/// crossing year boundary, full ISO 8601 on hover.
String formatGraphDate(DateTime commitDate, DateTime now) {
  final difference = now.difference(commitDate);

  // Less than 24 hours: show relative time
  if (difference.inHours < 24) {
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    return '${difference.inHours}h ago';
  }

  // >= 1 day: show absolute date
  final isSameYear = commitDate.year == now.year;
  if (isSameYear) {
    return '${_monthAbbr(commitDate.month)} ${commitDate.day}';
  }
  return '${_monthAbbr(commitDate.month)} ${commitDate.day}, ${commitDate.year}';
}

/// Returns the full ISO 8601 timestamp for use in tooltips.
String formatGraphDateTooltip(DateTime commitDate) {
  return commitDate.toIso8601String();
}

String _monthAbbr(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[month - 1];
}
