part of 'node.dart';

/// Indicates how each [Node] is presented in the serialized yaml string.
enum NodeStyle {
  /// A style that depends on indentation to indicate its structure
  block,

  /// A style that uses explicit indicators to present its structure
  flow,
}

/// Indicates how each [Scalar] is presented in a serialized yaml string.
enum ScalarStyle {
  /// A `block` style that starts with an explicit `|`.
  literal(NodeStyle.block),

  /// A `block` style that starts with an explicit `>`
  folded(NodeStyle.block),

  /// A `flow` style that is unquoted with no explicit `start` and `end`
  /// indicators.
  plain(NodeStyle.flow),

  /// A quoted `flow` style that uses `'`.
  singleQuoted(NodeStyle.flow),

  /// A quoted `flow` style that uses `"`.
  doubleQuoted(NodeStyle.flow);

  const ScalarStyle(this._nodeStyle);

  /// A basic [NodeStyle] used by the [YamlScalar]
  final NodeStyle _nodeStyle;

  /// Returns `true` if the scalar is serialized as [NodeStyle.block]
  bool get isBlockStyle => _nodeStyle == NodeStyle.block;
}

/// Controls how final line breaks and trailing empty lines are interpreted.
enum ChompingIndicator {
  /// Indicates the final line break and any trailing empty lines should be
  /// excluded from the scalar's content.
  strip('-'),

  /// Default if no explicit [ChompingIndicator] is provided. Indicates the
  /// final line break should be preserved in the scalar's content. Any
  /// trailing empty lines should be excluded.
  clip(''),

  /// Indicates the final line break and any trailing empty lines should be
  /// included as part of the scalar's content.
  keep('+');

  const ChompingIndicator(this.indicator);

  /// [NodeStyle.block] indicator for a [Scalar]
  final String indicator;
}
