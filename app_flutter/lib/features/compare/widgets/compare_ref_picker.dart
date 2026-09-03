import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// What kind of thing a [CompareRefOption] names -- purely for icon choice,
/// see spec page 12's "branch/tag/commit/stash/working copy 混一份，以圖示
/// 區分" (one mixed searchable list, distinguished by icon).
enum CompareRefOptionKind { branch, tag, stash, workingCopy, revision }

/// One entry in a [CompareRefPicker]'s option list.
///
/// [value] is null only for [CompareRefOptionKind.workingCopy] -- selecting
/// it calls [CompareRefPicker.onChanged] with null, which
/// `CompareTabSpec.right == null` treats as "compare with the live working
/// tree" (see compare_tabs_repository.dart).
@immutable
class CompareRefOption {
  const CompareRefOption({required this.kind, required this.label, this.value});

  final CompareRefOptionKind kind;
  final String label;
  final String? value;

  IconData get icon => switch (kind) {
    CompareRefOptionKind.branch => Icons.call_split,
    CompareRefOptionKind.tag => Icons.label_outline,
    CompareRefOptionKind.stash => Icons.inbox_outlined,
    CompareRefOptionKind.workingCopy => Icons.edit_note,
    CompareRefOptionKind.revision => Icons.commit,
  };
}

/// Searchable dropdown mixing branch/tag/stash/working-copy options (spec
/// page 12), plus freeform entry for any revision expression git accepts
/// (a raw commit oid, `HEAD~3`, ...) that isn't in [options].
///
/// A thin [RawAutocomplete] wrapper rather than a hand-rolled overlay --
/// it already gives keyboard navigation, filtering, and overlay positioning
/// for free; only the field/options rendering is customized to carry
/// [CompareRefOption.icon] and to accept freeform text on submit.
///
/// [RawAutocomplete] and not the [Autocomplete] convenience wrapper, and
/// stateful and not stateless, for one reason: `Autocomplete.initialValue`
/// is read once, when its own State is built, so nothing a later [value]
/// says ever reaches the field. Swap exchanges the two refs and re-fetches,
/// and both fields go on showing what they showed before -- the reported
/// defect. Owning the controller here is what lets [didUpdateWidget] put
/// the new value in it.
class CompareRefPicker extends StatefulWidget {
  const CompareRefPicker({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<CompareRefOption> options;

  /// The currently selected ref, or null for Working Copy.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<CompareRefPicker> createState() => _CompareRefPickerState();
}

class _CompareRefPickerState extends State<CompareRefPicker> {
  late final TextEditingController _controller = TextEditingController(
    text: _displayValue,
  );
  late final FocusNode _focusNode = FocusNode();

  /// Null is Working Copy, and the text for it is the option's *label*, not
  /// the value -- copying [CompareRefPicker.value] verbatim would blank the
  /// field rather than name the side.
  String get _displayValue =>
      widget.value ??
      widget.options
          .firstWhere(
            (CompareRefOption o) => o.kind == CompareRefOptionKind.workingCopy,
            orElse: () => const CompareRefOption(
              kind: CompareRefOptionKind.workingCopy,
              label: 'Working Copy',
            ),
          )
          .label;

  @override
  void didUpdateWidget(CompareRefPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Gated on `value`, never on the rendered text: typing does not change
    // `value`, so an in-progress query is never clobbered from here.
    if (widget.value == oldWidget.value) return;
    final String next = _displayValue;
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<CompareRefOption> options = widget.options;
    final ValueChanged<String?> onChanged = widget.onChanged;

    return RawAutocomplete<CompareRefOption>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (CompareRefOption option) => option.label,
      optionsBuilder: (TextEditingValue query) {
        if (query.text.isEmpty) return options;
        final String needle = query.text.toLowerCase();
        return options.where(
          (CompareRefOption o) => o.label.toLowerCase().contains(needle),
        );
      },
      onSelected: (CompareRefOption option) => onChanged(option.value),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space2,
                vertical: GbmSpacing.space2,
              ),
              filled: true,
              fillColor: colors.surfacePanelRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
                borderSide: BorderSide(color: colors.borderDefault),
              ),
            ),
            onSubmitted: (String text) {
              // Enter without picking a suggestion: accept it as a freeform
              // revision expression (a raw oid, HEAD~3, ...) rather than
              // discarding it, since git accepts far more than what's in
              // `options`.
              onChanged(text.isEmpty ? null : text);
              onFieldSubmitted();
            },
          ),
      optionsViewBuilder: (context, onSelected, matches) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          color: colors.surfaceOverlay,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 320),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: <Widget>[
                for (final CompareRefOption option in matches)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      option.icon,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    title: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textPrimary,
                      ),
                    ),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
