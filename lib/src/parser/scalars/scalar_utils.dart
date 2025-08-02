import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:source_span/source_span.dart';

/// A non-existent indent level if a scalar was parsed correctly.
///
/// Acts as an indicator on if the end of parsing to a scalar with block(-like)
/// syles, that is, `plain`, `literal` and `folded`, was not as a result of an
/// indent change.
const seamlessIndentMarker = -2;

typedef PreScalar = ({
  /// Multiline view of the content
  Iterable<String> content,

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

  /// Indicates whether the [parsedContent] has a line break.
  ///
  /// `NOTE`: This is a helper to prevent a redundant scan on the
  /// [parsedContent] as the line break may have already been seen while parsing
  /// the content.
  bool hasLineBreak,

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

// /// Infers native type for the value parsed for the [Scalar] and provides a
// /// default schema tag.
// PreScalar preformatScalar(
//   ScalarBuffer buffer, {
//   required ScalarStyle scalarStyle,
//   required int actualIdent,
//   required bool foundLinebreak,
//   required SourceLocation end,
//   bool trim = false,
//   int indentOnExit = seamlessIndentMarker,
//   DocumentMarker docMarkerType = DocumentMarker.none,
// }) {
//   var content = buffer.bufferedString();

//   if (trim) {
//     content = content.trim();
//   }

//   var normalized = content.toLowerCase();

//   dynamic value = content;
//   int? radix;
//   LocalTag tag = stringTag;

//   // Attempt to infer a default value
//   if (!foundLinebreak) {
//     if (_parseInt(normalized) case _ParsedInt(
//       radix: final pRadix,
//       value: final pValue,
//     )) {
//       radix = pRadix;
//       value = pValue;
//       tag = integerTag;
//     } else if (_isNull(normalized)) {
//       value = null;
//       tag = nullTag;
//     } else if (bool.tryParse(normalized) case bool boolean) {
//       value = boolean;
//       tag = booleanTag;
//     } else if (double.tryParse(normalized) case double parsedFloat) {
//       value = parsedFloat;
//       tag = floatTag;
//     }
//   }

//   return PreScalar._(
//     inferredYamlTag: tag,
//     scalarStyle: scalarStyle,
//     parsedContent: content,
//     docMarkerType: docMarkerType,
//     hasLineBreak: foundLinebreak,
//     inferredValue: value,
//     scalarIndent: actualIdent,
//     indentOnExit: indentOnExit,
//     end: end,
//     radix: radix,
//   );
// }

bool _isNull(String value) {
  return value.isEmpty || value == '~' || value == 'null';
}

const _octalPrefix = '0o';

typedef _ParsedInt = ({int value, int radix});

/// Parses an [int] and returns its value and radix.
_ParsedInt? _parseInt(String normalized) {
  int? radix;

  if (normalized.startsWith(_octalPrefix)) {
    normalized = normalized.replaceFirst(_octalPrefix, '');
    radix = 8;
  }

  // Check other bases used by YAML only if null
  radix ??= normalized.startsWith('0x') ? 16 : 10;

  if (int.tryParse(normalized, radix: radix) case int parsedInt) {
    return (value: parsedInt, radix: radix);
  }

  return null;
}
