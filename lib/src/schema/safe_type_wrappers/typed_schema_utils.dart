part of 'scalar_value.dart';

/// Regex for `null`
final _nullRegex = RegExp(r'[null|Null|NULL|~]');

/// Prefix for a `YAML` octal
const _octalPrefix = '0o';

/// Prefix for a `YAML` hexadecimal
const _hexPrefix = '0x';

/// A record represent an [int] and its `radix`
typedef _ParsedInt = ({int value, int radix});

/// Parses an [int] and returns its value and radix.
_ParsedInt? _parseInt(String normalized) {
  int? radix;

  if (normalized.startsWith(_octalPrefix)) {
    normalized = normalized.replaceFirst(_octalPrefix, '');
    radix = 8;
  }

  // Check other bases used by YAML only if null
  radix ??= normalized.startsWith(_hexPrefix) ? 16 : 10;

  if (int.tryParse(normalized, radix: radix) case int parsedInt) {
    return (value: parsedInt, radix: radix);
  }

  return null;
}

/// Converts an integer [value] to a string in the given [radix]
String _stringFromSafeInt(int value, int radix) {
  final prefix = switch (radix) {
    8 => _octalPrefix,
    16 => _hexPrefix,
    _ => '',
  };

  return '$prefix${value.toRadixString(radix)}';
}

/// A record for an inferred type [T]
typedef _MaybeInferred<T> = (LocalTag? tag, T? value);

/// A record categorizing an inferred value to a scalar value and its
/// associated tag in `YAML`
typedef _InferredScalarValue<T> = _MaybeInferred<ScalarValue<T>>;

/// Value not inferred
const _notInferred = (null, null);

/// Attempts to parse the [content] as a valid `Dart` type that is not an [int]
_MaybeInferred<T> _inferDartType<T>(String content) {
  if (double.tryParse(content) case double parsedFloat) {
    return (floatTag, parsedFloat as T);
  } else if (Uri.tryParse(content) case Uri uri) {
    return (uriTag, uri as T);
  } else if (bool.tryParse(content) case bool boolean) {
    /// - Just "true" and "false". Schema should be language specific but also
    ///   agnostic when representing values. Booleans are lowercase in Dart
    /// - Ignores "True", "False", "TRUE", "FALSE"
    return (booleanTag, boolean as T);
  }

  return _notInferred;
}

/// Infers a [ScalarValue] that is either `null` or not an [int]
_InferredScalarValue<T> _inferDartValue<T>(String content) {
  if (_nullRegex.hasMatch(content)) {
    return (nullTag, NullView(content) as ScalarValue<T>);
  } else if (_inferDartType(content) case (LocalTag dartTag, T dartType)) {
    return (dartTag, DartValue(dartType));
  }

  return _notInferred;
}

/// Infers a `YAML` [LocalTag] and a [ScalarValue] if a tag was never parsed.
({LocalTag inferredTag, ScalarValue<T> schema}) _inferSchema<T>(
  Iterable<String> content,
) {
  final inlined = content.join();

  if (_parseInt(inlined) case (:final radix, :final value)) {
    return (
      inferredTag: integerTag,
      schema: YamlSafeInt(value, radix) as ScalarValue<T>,
    );
  } else if (_inferDartValue(inlined) case (
    LocalTag normieTag,
    ScalarValue<T> normieSchema,
  )) {
    return (inferredTag: normieTag, schema: normieSchema);
  }

  return (
    inferredTag: stringTag,
    schema: StringView(content) as ScalarValue<T>,
  );
}

/// Infers a [ScalarValue] from a [parsedTag].
///
/// Internally calls [_inferSchema] and checks if the inferred tag matches
/// the [parsedTag].
ScalarValue<T> _schemaFromTag<T>(Iterable<String> content, LocalTag parsedTag) {
  /// Lazy implementation. Instead of duplicating code, just infer the type
  /// (thought not performant, we have a limited number). Represent partially
  /// as a string if the inferred tag doesn't match our parsed tag.
  if (_inferSchema<T>(content) case (
    :final inferredTag,
    :final schema,
  ) when inferredTag == parsedTag || inferredTag == stringTag) {
    return schema;
  }

  return StringView(content) as ScalarValue<T>;
}
