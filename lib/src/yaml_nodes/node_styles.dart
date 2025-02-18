/// Indicates how each [YamlNode] is presented in the serialized yaml string.
enum NodeStyle {
  /// A style that depends on indentation to indicate its structure
  block,

  /// A style that uses explicit indicators to present its structure
  flow,
}

/// An alias for a [NodeStyle] specific to any [YamlNode] that is a collection
/// such as a sequence (list) or mapping (map).
typedef CollectionStyle = NodeStyle;

/// Indicates how each [YamlScalar] is presented in a serialized yaml string.
enum ScalarStyle {
  /// A `block` style that starts with an explicit `|`.
  literal(NodeStyle.block),

  /// A `block` style that starts with an explicit `>`
  folded(NodeStyle.block),

  /// A `flow` style that is unquoted with no explicit `start` and `end`
  /// indicators
  plain(NodeStyle.flow),

  /// A quoted `flow` style that uses `'`.
  singleQuoted(NodeStyle.flow),

  /// A quoted `flow` style that uses `"`.
  doubleQuoted(NodeStyle.flow);

  const ScalarStyle(this.nodeStyle);

  /// A basic [NodeStyle] used by the [YamlScalar]
  final NodeStyle nodeStyle;

  /// Returns `true` if [NodeStyle.block]. Otherwise, `false`.
  bool get isBlockStyle => nodeStyle == NodeStyle.block;

  /// Returns `true` if [NodeStyle.flow]. Otherwise, `false`.
  bool get isFlowStyle => !isBlockStyle;
}

/// Controls how final line breaks and trailing empty lines are interpreted.
enum ChompingIndicator {
  /// Indicates the final line break and any trailing empty lines should be
  /// excluded from the scalar's content.
  strip('-'),

  /// Default if no explicit [ChompingIndicator] is provided. Indicates the
  /// final line break should be preserved in the scalar's content. Any
  /// trailing empty lines should be excluded.
  clip(null),

  /// Indicates the final line break and any trailing empty lines should be
  /// included as part of the scalar's content.
  keep('+');

  const ChompingIndicator(this._char);

  /// Represents its indicator
  final String? _char;

  /// Returns the character indicating how it should be presented
  String get indicator => _char ?? '';
}
