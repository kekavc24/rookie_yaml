part of 'yaml_node.dart';

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

enum DocumentMarker {
  /// Indicates the end of any documents and implies the start of a document.
  ///
  /// This marker must be used after declaring the document directives to
  /// indicate the start of the current document.
  ///
  /// If used while parsing a document (not its directives), the parser
  /// immediately terminates the current document and can be called again to
  /// parse the next document. In this case, the next documents must not
  /// declare any directives.
  ///
  /// ```yaml
  /// %SOME-DIRECTIVE this-is-fake
  /// --- # End of directive, start of document
  ///     # Parser scans for document starting point
  ///
  /// key: value
  ///
  /// ---- # End of document, Start of another document
  ///      # Parser scans for document starting point.
  /// value
  ///
  /// --- # End of document, Will throw if directives are declared in next
  ///     # document
  ///
  /// %OOPS not-allowed
  /// ```
  directiveEnd('---', stopIfParsingDoc: true),

  /// Indicates the end of the current document
  documentEnd('...', stopIfParsingDoc: true),

  /// No document markers.
  none('', stopIfParsingDoc: false);

  const DocumentMarker(
    this.indicator, {
    required this.stopIfParsingDoc,
  });

  /// Representation in a `YAML` source string
  final String indicator;

  /// Indicates if parser should stop parsing a document.
  final bool stopIfParsingDoc;

  static DocumentMarker ofString(String marker) => switch (marker.trim()) {
    '---' => DocumentMarker.directiveEnd,
    '...' => DocumentMarker.documentEnd,
    _ => DocumentMarker.none,
  };
}
