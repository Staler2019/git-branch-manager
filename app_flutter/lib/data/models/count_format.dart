/// `12480` → `12,480`, always with a comma whatever the locale: the mock's
/// own figures. One left-to-right pass over the digits. Shared by the status
/// bar's progress label and the clone-progress label the Log's running row
/// carries.
String formatCount(int n) {
  final String digits = n.toString();
  if (digits.length <= 3) return digits;
  int first = digits.length % 3;
  if (first == 0) first = 3;
  final StringBuffer out = StringBuffer(digits.substring(0, first));
  for (int i = first; i < digits.length; i += 3) {
    out
      ..write(',')
      ..write(digits.substring(i, i + 3));
  }
  return out.toString();
}
