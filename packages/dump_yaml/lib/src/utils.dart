import 'package:rookie_yaml/rookie_yaml.dart';

/// Default YAML style that is widely used.
const classicScalarStyle = ScalarStyle.plain;

extension Styling on NodeStyle {
  /// Whether [NodeStyle.block].
  bool get isBlock => this == NodeStyle.block;

  /// Whether [NodeStyle.flow].
  bool get isFlow => !isBlock;

  /// Whether `this` style is compatible with the [other] style.
  ///
  /// Flow [NodeStyle]s cannot contain embedded [NodeStyle.block] nodes.
  bool isIncompatible(NodeStyle other) => isFlow && other.isBlock;
}

extension StringUtils on String {
  /// Applies the [indent].
  String indented(int indent) => '${' ' * indent}$this';

  /// Applies the node's properties inline. This is usually all scalars and
  /// flow collections.
  String applyInline({String? tag, String? anchor, String? node}) {
    var dumped = node ?? this;

    void apply(String? prop, [String prefix = '']) {
      if (prop == null) return;
      dumped = '$prefix$prop $dumped';
    }

    apply(tag);
    apply(anchor, '&');
    return dumped;
  }

  /// Applies the [tag] and [anchor] in its own line just before the [node].
  /// Apply to block collections only.
  String applyBlock(
    int indent, {
    required String lineEnding,
    String? tag,
    String? anchor,
  }) {
    // Inline the properties and check if any are present.
    // PS: This "if-case" is intentional. Expressive :)
    if (applyInline(tag: tag, anchor: anchor, node: '').trim()
        case final properties when properties.isNotEmpty) {
      return '$properties$lineEnding${trimLeft().indented(indent)}';
    }

    return this;
  }
}
