/// The one place a management panel's persisted-layout key is spelled.
///
/// P19 樣板規則 1 says each tab remembers its own splitter position. Before
/// this function the rule was implemented as thirteen hand-written strings
/// across twelve files, three of which carried a `:${widget.path}` suffix and
/// nine of which did not — with a test standing next to them saying the nine
/// were a blessed exception. Nothing checked that no two of the thirteen
/// collided, and two panels sharing a key share a splitter position silently.
///
/// **The suffix rule is derived, not decided here.** It comes from
/// [GbmPanelKind.isPerSubject], which is the same property
/// `PanelTabsNotifier.open()` uses to decide whether asking for a panel again
/// gives you a second tab or the one you already had. So 「can two of these
/// exist at once」 and 「does the key tell them apart」 are two faces of one
/// fact rather than two decisions someone has to keep in step.
///
/// **Deliberately not keyed on the tab id.** That is the literal maximal
/// reading of 「各自」 and it is wrong: a tab id is `'${kind.slug}-${_nextId++}'`
/// from an in-memory counter, and `PanelTabsNotifier` persists nothing — so
/// keying on it would lose every splitter width across a restart, and worse,
/// collide, because this run's `blame-0` is next run's different file
/// inheriting a stranger's width.
library;

import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';

/// The `panelLayout.*` storage id for [kind]'s splitter.
///
/// [subject] is the file a per-subject panel is about; it is ignored for the
/// nine singleton kinds, because `open()` normalises their subject to null
/// and no second tab can exist to be told apart.
///
/// [slot] names a *second* splitter inside one panel — `manage-stashes` has
/// one for its detail pane. It is a suffix on the kind rather than a separate
/// id so a panel's keys sort together and share one prefix filter.
String panelStorageId(GbmPanelKind kind, {String? subject, String? slot}) {
  final StringBuffer id = StringBuffer('panel.${kind.slug}');
  if (slot != null) id.write('.$slot');
  if (kind.isPerSubject && subject != null) id.write(':$subject');
  return id.toString();
}
