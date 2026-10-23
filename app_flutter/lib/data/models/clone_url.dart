/// The folder `git clone <url>` would create with no directory given:
/// the last path segment, without a trailing `/`, `.git` or `/.git`. Works
/// for URLs, scp syntax (`git@host:org/repo`) and local paths. Empty when
/// nothing is left -- the caller then leaves the destination alone.
///
/// A character no folder name may hold on Windows or macOS (`< > " | ? *`
/// and control characters; the separators and `:` already cut the segment)
/// becomes `_`, so the name can always be created.
///
/// Fills the Clone dialog's destination as the URL is typed (DLGS:
/// 「URL 貼上後自動帶出資料夾名，可手改」).
String cloneFolderNameFromUrl(String url) {
  String s = _trimSeparators(url.trim());
  // `/.git` needs no case of its own: dropping `.git` leaves a separator,
  // which the trim takes.
  if (s.endsWith('.git')) {
    s = _trimSeparators(s.substring(0, s.length - 4));
  }
  final int cut = s.lastIndexOf(RegExp(r'[/\\:]'));
  final String name = cut < 0 ? s : s.substring(cut + 1);
  return name.replaceAll(RegExp(r'[<>"|?*\x00-\x1f]'), '_');
}

/// The Clone dialog's destination for [parent] (C-D1, 「選的是上層」):
/// [parent] plus the folder [url] names, or [parent] itself while the URL
/// names none.
String cloneDestinationPath(String parent, String url) {
  final String base = _trimSeparators(parent);
  final String name = cloneFolderNameFromUrl(url);
  return name.isEmpty ? base : '$base/$name';
}

String _trimSeparators(String s) => s.replaceAll(RegExp(r'[/\\]+$'), '');
