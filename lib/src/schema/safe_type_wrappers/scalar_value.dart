import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'typed_schema_utils.dart';

/// A wrapper class that safely wraps types inferred from content parsed
/// within a scalar.
sealed class ScalarValue<T> {
  ScalarValue();

  /// Inferred value
  T get value;

  /// Creates a wrapped [ScalarValue] for the parsed [content].
  ///
  /// If [defaultToString] is `true` (content spans more that 1 line or the
  /// scalar has a [TypeResolverTag]), this defaults to a [StringView].
  /// Otherwise, attempts to infer its kind based on available `Dart` types.
  /// See [PreScalar]
  ///
  /// Similarly, if [parsedTag] is not `null` and it is a valid `YAML` tag,
  /// its type is inferred. Defaults to a [StringView] otherwise.
  ///
  /// [ifParsedTagNull] is used to provide an inferred [TagShorthand] to a
  /// scalar based on its kind (valid Dart type) if [parsedTag] is `null`
  /// (no tag was parsed).
  factory ScalarValue.fromParsedScalar(
    String content, {
    required bool defaultToString,
    required TagShorthand? parsedTag,
    required void Function(TagShorthand inferred) ifParsedTagNull,
  }) {
    /// Anything spanning more than one line is a string and we cannot infer
    /// its type
    if (!defaultToString) {
      if (parsedTag != null) {
        return _schemaFromTag<T>(content, parsedTag);
      }

      final (:inferredTag, :schema) = _inferSchema<T>(content);
      ifParsedTagNull(inferredTag);
      return schema;
    }

    if (parsedTag == null) ifParsedTagNull(stringTag);
    return DartValue(content) as ScalarValue<T>;
  }

  @override
  String toString() => value.toString();
}

/// Any `Dart` type abstraction.
abstract base class _InferredValue<T> extends ScalarValue<T> {
  _InferredValue(this.value);

  @override
  final T value;
}

/// A safe representation of an integer parsed from a `YAML` source string.
/// This wrapper guarantees that an integer will be dumped in the same form
/// as it was parsed.
final class YamlSafeInt extends _InferredValue<int> {
  YamlSafeInt(super.value, this.radix);

  /// A valid number base
  final int radix;

  @override
  String toString() => _stringFromSafeInt(value, radix);
}

/// A wrapper class for `null`. While it may seem counterintuitive, some
/// `null`s in `YAML` cannot be represented/non-existent but are implicit such
/// as:
///   - Missing key from a flow/block map
///   - Missing value from a block list
final class NullView extends _InferredValue<String?> {
  NullView(String nullStr)
    : _null = nullStr.isEmpty ? 'null' : nullStr,
      super(null);

  final String _null;

  @override
  String toString() => _null;
}

/// Any `Dart` value that is not an [int] or [null]
final class DartValue<T> extends _InferredValue<T> {
  DartValue(super.value);
}

/// A value inferred using a custom [ContentResolver] tag.
final class CustomValue<T> extends _InferredValue<T> {
  CustomValue(super.value, {required this.toYamlSafe});

  /// Maps the [T] object back to a dumpable string.
  final String Function(T value) toYamlSafe;

  @override
  String toString() => toYamlSafe(value);
}
