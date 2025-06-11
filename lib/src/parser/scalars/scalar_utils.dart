import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

/// A non-existent indent level if a scalar was parsed correctly.
///
/// Acts as an indicator on if the end of parsing to a scalar with block(-like)
/// syles, that is, `plain`, `literal` and `folded`, was not as a result of an
/// indent change.
const seamlessIndentMarker = -2;

/// An intermediate [Scalar] wrapper obtained after a [Scalar] is parsed.
final class PreScalar {
  PreScalar._({
    required this.inferredYamlTag,
    required this.scalarStyle,
    required this.parsedContent,
    required this.hasDocEndMarkers,
    required this.hasLineBreak,
    required this.inferredValue,
    required this.scalarIndent,
    required this.indentOnExit,
    this.radix,
  }) : indentDidChange = indentOnExit != seamlessIndentMarker;

  /// Implicit `YAML` tag inferred based on the generic schema. May need
  /// resolution from the parser if no recognized schema tag was specified.
  LocalTag inferredYamlTag;

  /// [Scalar]'s scalarstyle
  final ScalarStyle scalarStyle;

  /// Actual scalar content.
  final String parsedContent;

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
  final int scalarIndent;

  /// Returns `true` if any `---` or `...` was encountered
  final bool hasDocEndMarkers;

  /// Indicates whether the [parsedContent] has a line break.
  ///
  /// `NOTE`: This is a helper to prevent a redundant scan on the
  /// [parsedContent] as the line break may have already been seen while parsing
  /// the content.
  final bool hasLineBreak;

  /// Returns `true` for block(-like) styles, that is, `plain`, `literal` and
  /// `folded` if an indent change triggered the end of its parsing
  final bool indentDidChange;

  /// Indent after complete parsing of the scalar. This will usually
  /// default to `-2` for quoted styles.
  ///
  /// Block(-like) styles, that is, `plain`, `literal` and `folded`, that rely
  /// on indentation to convey content may provide a different value when
  /// [indentDidChange] is `true`.
  final int indentOnExit;

  /// Value inferred based on its kind as specified in the YAML generic
  /// schema
  dynamic inferredValue;

  /// Radix if [inferredValue] is an integer
  int? radix;

  set reformatWith(LocalTag tag) {
    if (tag == inferredYamlTag) return;

    dynamic value;
    int? radix;

    var canReformat = false;

    // Ensure we can reformat
    if (tag == integerTag) {
      if (_parseInt(parsedContent) case _ParsedInt(
        radix: final pRadix,
        value: final pValue,
      )) {
        value = pValue;
        radix = pRadix;
        canReformat = true;
      }
    } else if (tag == floatTag) {
      final float = double.tryParse(parsedContent);

      canReformat = float != null;
      value = float;
    } else if (tag == booleanTag) {
      final boolean = bool.tryParse(parsedContent, caseSensitive: false);

      canReformat = boolean != null;
      value = boolean;
    } else if (tag == nullTag && _isNull(parsedContent.toLowerCase())) {
      value = null;
      canReformat = true;
    }

    if (!canReformat) {
      value = parsedContent;
    }

    /// No need to overwrite the existing tag. That tag was inferred by
    /// default based on the schema
    this
      ..inferredValue = value
      ..radix = radix;
  }

  Scalar parsedScalar(Set<ResolvedTag> tags, Set<String> anchors) {
    return inferredValue is int
        ? IntScalar(
            inferredValue,
            radix: radix!,
            anchors: anchors,
            content: parsedContent,
            scalarStyle: scalarStyle,
            tags: tags,
          )
        : Scalar(
            inferredValue,
            content: parsedContent,
            scalarStyle: scalarStyle,
            anchors: anchors,
            tags: tags,
          );
  }
}

/// Infers native type for the value parsed for the [Scalar] and provides a
/// default schema tag.
PreScalar preformatScalar(
  ScalarBuffer buffer, {
  required ScalarStyle scalarStyle,
  required int actualIdent,
  bool trim = false,
  int indentOnExit = seamlessIndentMarker,
  bool hasDocEndMarkers = false,
}) {
  final hasLineBreak = buffer.hasLineBreaks;
  var content = buffer.bufferedString();

  if (trim) {
    content = content.trim();
  }

  var normalized = content.toLowerCase();

  dynamic value = content;
  int? radix;
  LocalTag tag = stringTag;

  // Attempt to infer a default value
  if (!hasLineBreak) {
    if (_parseInt(normalized) case _ParsedInt(
      radix: final pRadix,
      value: final pValue,
    )) {
      radix = pRadix;
      value = pValue;
      tag = integerTag;
    } else if (_isNull(normalized)) {
      value = null;
      tag = nullTag;
    } else if (bool.tryParse(normalized) case bool boolean) {
      value = boolean;
      tag = booleanTag;
    } else if (double.tryParse(normalized) case double parsedFloat) {
      value = parsedFloat;
      tag = floatTag;
    }
  }

  return PreScalar._(
    inferredYamlTag: tag,
    scalarStyle: scalarStyle,
    parsedContent: content,
    hasDocEndMarkers: hasDocEndMarkers,
    hasLineBreak: hasLineBreak,
    inferredValue: value,
    scalarIndent: actualIdent,
    indentOnExit: indentOnExit,
    radix: radix,
  );
}

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
