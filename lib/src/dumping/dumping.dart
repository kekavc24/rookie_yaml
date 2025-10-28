import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'dump_mapping.dart';
part 'dump_scalar.dart';
part 'dump_sequence.dart';
part 'dump_yaml_node.dart';
part 'unfolding.dart';

extension Normalizer on int {
  /// Normalizes all character that can be escaped.
  ///
  /// If [includeTab] is `true`, then `\t` is also normalized. If
  /// [includeLineBreaks] is `true`, both `\n` and `\r` are normalized. If
  /// [includeSlashes] is `true`, backslash `\` and slash `/` are escaped. If
  /// [includeDoubleQuote] is `true`, the double quote is escaped.
  Iterable<int> normalizeEscapedChars({
    required bool includeTab,
    required bool includeLineBreaks,
    bool includeSlashes = true,
    bool includeDoubleQuote = true,
  }) sync* {
    int? leader = backSlash;
    var trailer = this;

    switch (this) {
      case unicodeNull:
        trailer = 0x30;

      case bell:
        trailer = 0x61;

      case asciiEscape:
        trailer = 0x65;

      case nextLine:
        trailer = 0x4E;

      case nbsp:
        trailer = 0x5F;

      case lineSeparator:
        trailer = 0x4C;

      case paragraphSeparator:
        trailer = 0x50;

      case backspace:
        trailer = 0x62;

      case tab when includeTab:
        trailer = 0x74;

      case lineFeed when includeLineBreaks:
        trailer = 0x6E;

      case verticalTab:
        trailer = 0x76;

      case formFeed:
        trailer = 0x66;

      case carriageReturn when includeLineBreaks:
        trailer = 0x66;

      case backSlash || slash:
        {
          if (includeSlashes) break;
          leader = null;
        }

      case doubleQuote:
        {
          if (includeDoubleQuote) break;
          leader = null;
        }

      default:
        leader = null; // Remove nerf by default
    }

    if (leader != null) yield leader;
    yield trailer;
  }
}

/// Joins [lines] of a scalar being dumped by applying the specified [indent]
/// to each line. If [includeFirst] is `true`, the first line is also indented.
(String joinIndent, String joined) _joinScalar(
  Iterable<String> lines, {
  required int indent,
  bool includeFirst = false,
}) {
  final joinIndent = ' ' * indent;
  return (
    joinIndent,
    lines
        .mapIndexed(
          (i, l) =>
              (includeFirst || i != 0) && l.isNotEmpty ? '$joinIndent$l' : l,
        )
        .join('\n'),
  );
}

/// Splits [blockContent] for a scalar to be encoded as [ScalarStyle.folded] or
/// [ScalarStyle.literal].
Iterable<String> _splitBlockString(String blockContent) => splitLazyChecked(
  blockContent,
  replacer: (index, char) sync* {
    if (!char.isPrintable()) {
      throw FormatException(
        'Non-printable character cannot be encoded as literal/folded',
        blockContent,
        index,
      );
    }

    yield char;
  },
  lineOnSplit: () {},
);

typedef _DumpedObjectInfo = ({
  bool explicitIfKey,
  bool isFlow,
  bool isCollection,
  String encoded,
});

typedef _UnpackedCompact = ({
  String? encodedAlias,
  String? properties,
  NodeStyle? styleOverride,
  Object? toEncode,
});

/// Encodes any [object] to valid `YAML` source string. If [jsonCompatible] is
/// `true`, the object is encoded as valid json with collections defaulting to
/// [NodeStyle.flow] and scalars encoded with [ScalarStyle.doubleQuoted].
///
/// In addition to encoding the [object], it indicates if the source string can
/// be an explicit key in a `YAML` [Mapping] and if the [object] was a
/// collection.
///
/// The [object] is always an explicit key if it is a collection or was
/// [Scalar]-like and span multiple lines.
///
/// If an [unpack]ing function is provided and the [object] is a
/// [CompactYamlNode], its properties will be included the string.
_DumpedObjectInfo _encodeObject<T>(
  T object, {
  required int indent,
  required bool jsonCompatible,
  required NodeStyle nodeStyle,
  required ScalarStyle? currentScalarStyle,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
  ScalarStyle? mapKeyScalarStyle,
  ScalarStyle? mapValueScalarStyle,
}) {
  Object? encodable;
  String? objectProperties;
  var style = nodeStyle;

  bool isFlow() => style == NodeStyle.flow;

  if (unpack != null && object is CompactYamlNode) {
    final (:encodedAlias, :properties, :toEncode, :styleOverride) = unpack(
      object,
    );

    // Incase the alias is linked correctly
    if (encodedAlias != null) {
      return (
        encoded: encodedAlias,
        isFlow: isFlow(),
        isCollection: false,
        explicitIfKey: false,
      );
    }

    /// Only block styles can be overriden in case the child has node properties
    style = styleOverride != null && style != NodeStyle.flow
        ? styleOverride
        : style;
    encodable = toEncode;
    objectProperties = properties;
  }

  encodable ??= switch (object) {
    AliasNode(:final aliased) => aliased,
    _ => object,
  };

  switch (encodable) {
    case Iterable list:
      return (
        explicitIfKey: true,
        isFlow: isFlow(),
        isCollection: true,
        encoded: _dumpSequence(
          list,
          indent: indent,
          collectionNodeStyle: style,
          jsonCompatible: jsonCompatible,
          preferredScalarStyle: currentScalarStyle,
          unpack: unpack,
          properties: objectProperties,
        ),
      );

    case Map map:
      return (
        explicitIfKey: true,
        isFlow: isFlow(),
        isCollection: true,
        encoded: _dumpMapping(
          map,
          indent: indent,
          collectionNodeStyle: style,
          jsonCompatible: jsonCompatible,
          keyScalarStyle: mapKeyScalarStyle ?? currentScalarStyle,
          valueScalarStyle: mapValueScalarStyle ?? currentScalarStyle,
          unpack: unpack,
          properties: objectProperties,
        ),
      );

    default:
      {
        final (:explicitIfKey, :encodedScalar) = _dumpScalar(
          encodable,
          indent: indent,
          jsonCompatible: jsonCompatible,
          parentNodeStyle: style,

          /// Always prefer a Scalar's scalar style in case nothing is present.
          /// A node style will enforce its default style if a scalar style's
          /// node style is invalid.
          dumpingStyle:
              currentScalarStyle ??
              (encodable is Scalar ? encodable.scalarStyle : null),
        );

        return (
          explicitIfKey: explicitIfKey,
          isFlow: isFlow(),
          isCollection: false,
          encoded: _applyProperties(encodedScalar, objectProperties),
        );
      }
  }
}

/// Dumps an [object] that is a sequence entry.
_DumpedObjectInfo _dumpListEntry<T>(
  T object, {
  required int indent,
  required bool jsonCompatible,
  required NodeStyle nodeStyle,
  required ScalarStyle? currentScalarStyle,
  required _UnpackedCompact Function(CompactYamlNode object)? unpack,
}) => _encodeObject(
  object,
  indent: indent,
  jsonCompatible: jsonCompatible,
  nodeStyle: nodeStyle,
  currentScalarStyle: currentScalarStyle,
  mapKeyScalarStyle: currentScalarStyle,
  mapValueScalarStyle: currentScalarStyle,
  unpack: unpack,
);

/// Replaces an empty [string] with an explicit `null`.
String _replaceIfEmpty(String string) => string.isEmpty ? 'null' : string;

/// Applies an [encoded] node's [properties] limited to a tag and/or anchor
/// with the [separator] added between them if the [properties] is not `null`.
String _applyProperties(
  String encoded,
  String? properties, {
  String separator = ' ',
}) => properties == null || properties.isEmpty
    ? encoded
    : '$properties$separator$encoded';

/// Dumps a [Scalar] or any `Dart` object by calling its `toString` method.
///
/// [dumpingStyle] will always default to [ScalarStyle.doubleQuoted] if
/// [jsonCompatible] is `true`. In this case, the string is normalized and any
/// escaped characters are "nerfed".
///
/// {@category dump_scalar}
String dumpScalar<T>(
  T scalar, {
  int indent = 0,
  bool jsonCompatible = false,
  ScalarStyle dumpingStyle = ScalarStyle.doubleQuoted,
}) =>
    ' ' * indent +
    _dumpScalar(
      scalar,
      indent: indent,
      jsonCompatible: jsonCompatible,
      dumpingStyle: dumpingStyle,
    ).encodedScalar;

/// Dumps a [sequence] which must be a [Sequence] or `Dart` [List].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [sequence] is an actual [Sequence] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
///
/// [preferredScalarStyle] is a hint on the preferred [ScalarStyle] for
/// all scalars in your [sequence] (even map keys and values). If the `scalar`
/// is an actual [Scalar] object, its [ScalarStyle] takes precedence. Otherwise,
/// defaults to [preferredScalarStyle]. Furthermore, the
/// [preferredScalarStyle]'s [NodeStyle] must be compatible with the
/// [collectionNodeStyle] if present, that is, [NodeStyle.block] accepts both
/// `block` and `flow` styles while [NodeStyle.flow] accepts only `flow` styles.
/// If incompatible, [preferredScalarStyle] is ignored and defaults to
/// [ScalarStyle.doubleQuoted] in [NodeStyle.flow] and [ScalarStyle.literal] in
/// [NodeStyle.block].
///
/// If [preferredScalarStyle] is [ScalarStyle.plain] and has leading or
/// trailing whitespaces (line breaks included), the [ScalarStyle] defaults
/// to the [collectionNodeStyle]'s default.
///
/// {@category dump_sequence}
String dumpSequence<L extends Iterable>(
  L sequence, {
  int indent = 0,
  bool jsonCompatible = false,
  NodeStyle? collectionNodeStyle,
  ScalarStyle? preferredScalarStyle,
}) => _dumpSequence(
  sequence,
  indent: indent,
  isRoot: true,
  collectionNodeStyle: collectionNodeStyle,
  jsonCompatible: jsonCompatible,
  preferredScalarStyle: preferredScalarStyle,
  unpack: null,
  properties: null,
);

/// Dumps a [mapping] which must be a [Mapping] or `Dart` [Map].
///
/// [collectionNodeStyle] defaults to [NodeStyle.flow] if [jsonCompatible] is
/// `true`. If `null` and the [mapping] is an actual [Mapping] object, its
/// [NodeStyle] is used. Otherwise, [collectionNodeStyle] defaults to
/// [NodeStyle.flow].
///
/// [keyScalarStyle] is a hint on the preferred [ScalarStyle] for
/// scalars in your [mapping]. If the `scalar` is an actual [Scalar] object,
/// its [ScalarStyle] takes precedence. Otherwise, defaults to
/// [keyScalarStyle]. Furthermore, the [keyScalarStyle]'s
/// [NodeStyle] must be compatible with the [collectionNodeStyle] if present,
/// that is, [NodeStyle.block] accepts both `block` and `flow` styles while
/// [NodeStyle.flow] accepts only `flow` styles. If incompatible,
/// [keyScalarStyle] is ignored and defaults to [ScalarStyle.doubleQuoted]
/// in [NodeStyle.flow] and [ScalarStyle.literal] in [NodeStyle.block]. This
/// also applies to [valueScalarStyle] too.
///
/// If [keyScalarStyle] or [valueScalarStyle] is [ScalarStyle.plain] and has
/// leading or trailing whitespaces (line breaks included), the [ScalarStyle]
/// defaults to the [collectionNodeStyle]'s default.
///
/// {@category dump_mapping}
String dumpMapping<M extends Map>(
  M mapping, {
  int indent = 0,
  bool jsonCompatible = false,
  NodeStyle? collectionNodeStyle,
  ScalarStyle? keyScalarStyle,
  ScalarStyle? valueScalarStyle,
}) => _dumpMapping(
  mapping,
  indent: 0,
  isRoot: true,
  collectionNodeStyle: collectionNodeStyle,
  jsonCompatible: jsonCompatible,
  keyScalarStyle: keyScalarStyle,
  valueScalarStyle: valueScalarStyle,
  unpack: null,
  properties: null,
);
