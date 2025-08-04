import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'typed_schema_utils.dart';

/// A wrapper class that safely wraps types inferred from content parsed
/// within a scalar.
sealed class ScalarValue<T> {
  ScalarValue();

  /// Inferred value
  T get value;

  /// A sequential view of the string split at `\n`. This is useful when
  /// dumping the scalar
  Iterable<String> yamlSafe() => [toString()];

  /// Creates a wrapped [ScalarValue] for the parsed [content].
  ///
  /// If [contentHasLineBreak] is `true` or the [content] spans more than
  /// 1 line, this defaults to a [StringView]. Otherwise, attempts to infer
  /// to its kind based on available `Dart` types. See [PreScalar]
  ///
  /// Similarly, if [parsedTag] is not `null` and it is a valid `YAML` tag,
  /// its type is inferred. Defaults to a [StringView] otherwise.
  ///
  /// [ifParsedTagNull] is used to provide an inferred [LocalTag] to a scalar
  /// based on its kind (valid Dart type) if [parsedTag] is `null` (no tag
  /// was parsed).
  factory ScalarValue.fromParsedScalar(
    String content, {
    required bool contentHasLineBreak,
    required LocalTag? parsedTag,
    required void Function(LocalTag inferred) ifParsedTagNull,
  }) {
    /// Anything spanning more than one line is a string and we cannot infer
    /// its type
    if (!contentHasLineBreak) {
      if (parsedTag != null) {
        return _schemaFromTag<T>(content, parsedTag);
      }

      final (:inferredTag, :schema) = _inferSchema<T>(content);
      ifParsedTagNull(inferredTag);
      return schema;
    }

    if (parsedTag == null) ifParsedTagNull(stringTag);
    return StringView(content) as ScalarValue<T>;
  }

  @override
  String toString() => value.toString();
}

/// Any `Dart` type that is not a [String]
abstract base class _InferredValue<T> extends ScalarValue<T> {
  _InferredValue(this.value);

  @override
  final T value;
}

/// Default schema type for most scalars that resolve to string.
final class StringView extends _InferredValue<String> {
  StringView(super.value);

  @override
  Iterable<String> yamlSafe() => splitStringLazy(value);
}

/// A safe representation of an integer parsed from a `YAML` source string.
/// This wrapper guarantees that an integer will be dumped in the same form
/// as it was parsed.
final class YamlSafeInt extends _InferredValue<int> {
  YamlSafeInt(super.value, this.radix);

  /// A valid number base
  final int radix;

  @override
  Iterable<String> yamlSafe() sync* {
    yield _stringFromSafeInt(value, radix);
  }
}

/// A wrapper class for `null`. While it may seem counterintuitive, some
/// `null`s in `YAML` cannot be represented/non-existent but are implicit such
/// as:
///   - Missing key from a flow/block map
///   - Missing value from a block list
final class NullView extends _InferredValue<String?> {
  NullView(this._null) : isVirtual = _null.isEmpty, super(null);

  final String _null;

  /// Indicates if a `null` is non-existent
  final bool isVirtual;

  @override
  Iterable<String> yamlSafe() sync* {
    yield _null;
  }
}

/// Any `Dart` value that is not an [int], [null], or [String].
final class DartValue<T> extends _InferredValue<T> {
  DartValue(super.value);
}
