import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:source_span/source_span.dart';

/// A non-existent indent level for block(-like) scalars (`plain`, `literal`,
/// `folded`) that are affected by indent changes. Indicates that the said
/// scalar was parsed successfully without an indent change.
const seamlessIndentMarker = -2;

typedef PreScalar = ({
  /// Buffered content
  String content,

  /// [Scalar]'s scalarstyle
  ScalarStyle scalarStyle,

  /// Fixed indent used to parse the scalar.
  ///
  /// It should be noted that the indent for a flow scalar
  /// ([ScalarStyle.doubleQuoted], [ScalarStyle.singleQuoted]
  /// and [ScalarStyle.plain]) may be an approximate indent since indent serves
  /// no purpose in a flow scalar. Ergo, this [scalarIndent] may refer to the
  /// minimum indent used to determine its structure if its parent flow
  /// collection ([Sequence] or [Mapping]) is nested within a collection
  ///
  /// If the scalar is a direct child of a block key or block list then its
  /// indent is fixed based on the parent. However, for [ScalarStyle.folded]
  /// and [ScalarStyle.literal], this indent may be greater than that suggested
  /// by the parent since YAML allows block scalars to define their own
  /// indentation using the indentation indicator (`+`) in the block header.
  /// Additionally, YAML recommends the parser to infer the indent based
  /// on the first non-empty line's indentatio. This indent can be end up being
  /// equal to or greater than the indent recommended by the parent.
  int scalarIndent,

  /// Document marker type encountered
  DocumentMarker docMarkerType,

  /// Indicates whether any linebreak was ever seen while parsing.
  ///
  /// `NOTE`: This is a helper to prevent a redundant scan on the
  /// [parsedContent] as the line break may have already been seen while parsing
  /// the content and folded
  bool hasLineBreak,

  /// Indicates if the actual formatted content itself has a line break.
  ///
  /// Do not confuse this with `hasLineBreak`. Some scalars fold line breaks
  /// which are never written to the buffer. Specifically,
  /// [ScalarStyle.doubleQuoted] allow line breaks to be escaped. In this case,
  /// the string may be concantenated without ever folding the line break to a
  /// space. This information may be crucial to how we infer the kind
  /// (Dart type) since most (, if not all,) types are inline.
  bool wroteLineBreak,

  /// Returns `true` for block(-like) styles, that is, `plain`, `literal` and
  /// `folded` if an indent change triggered the end of its parsing
  bool indentDidChange,

  /// Indent after complete parsing of the scalar. This will usually
  /// default to `-2` for quoted styles.
  ///
  /// Block(-like) styles, that is, `plain`, `literal` and `folded`, that rely
  /// on indentation to convey content may provide a different value when
  /// [indentDidChange] is `true`.
  int indentOnExit,

  /// End offset of the scalar (exclusive)
  SourceLocation end,
});
