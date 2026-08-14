/// Represents a single column in the commit graph display.
///
/// Each column has visibility, lock status, width, and display order settings
/// that are persisted app-level via SharedPreferences.
class GraphColumn {
  const GraphColumn({
    required this.id,
    required this.label,
    required this.visible,
    required this.locked,
    required this.width,
    required this.order,
  });

  factory GraphColumn.fromJson(Map<String, dynamic> json) {
    return GraphColumn(
      id: json['id'] as String,
      label: json['label'] as String,
      visible: json['visible'] as bool,
      locked: json['locked'] as bool,
      width: (json['width'] as num).toDouble(),
      order: json['order'] as int,
    );
  }

  /// Unique identifier for this column (e.g., 'graph', 'message', 'refs').
  final String id;

  /// Display label for this column (e.g., 'Graph', 'Message', 'Author').
  final String label;

  /// True if this column should be displayed in the graph.
  final bool visible;

  /// True if this column cannot be hidden or reordered by the user.
  final bool locked;

  /// Display width in logical pixels.
  final double width;

  /// Position in the column display order (0 = leftmost).
  final int order;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'visible': visible,
    'locked': locked,
    'width': width,
    'order': order,
  };

  /// Creates a copy of this column with the specified fields replaced.
  GraphColumn copyWith({
    String? id,
    String? label,
    bool? visible,
    bool? locked,
    double? width,
    int? order,
  }) => GraphColumn(
    id: id ?? this.id,
    label: label ?? this.label,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    width: width ?? this.width,
    order: order ?? this.order,
  );
}
