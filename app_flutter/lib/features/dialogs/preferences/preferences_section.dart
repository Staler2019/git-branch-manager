/// The six sections of spec page 11's `PREFNAV`, in the spec's own order,
/// plus two user-requested ones that are not conformance items:
/// [developer] (fix/refresh-ui-first-tiering, same category as the soft-wrap
/// toggle in `docs/records/2026-10-04-soft-wrap-off-by-default.md`) and
/// [externalApps] (open-with-apps-spec.html, ruling D2: after Appearance).
///
/// Ruling: `docs/records/2026-10-04-developer-prefs-tab.md`
///
/// Its own file, with no imports, so `route_paths.dart` can name a section
/// in a URL without depending on the dialog's widgets.
enum PreferencesSection {
  general,
  repositorySources,
  git,
  appearance,
  externalApps,
  shortcuts,
  advanced,
  developer,
}
