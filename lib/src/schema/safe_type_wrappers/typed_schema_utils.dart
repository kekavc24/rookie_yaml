part of 'scalar_value.dart';

const _cr = 0x0D;
const _lf = 0x0A;

/// Splits a string lazily at `\r` or `\n` or `\r\n` which are recognized as
/// line breaks in YAML.
///
/// This function breaks the lines indiscriminately and does not track the
/// dominant line break based on the platform unless the `\r\n` is seen.
Iterable<String> splitStringLazy(String string) sync* {
  final runeIterator = string.runes.iterator;

  bool canIterate() => runeIterator.moveNext();

  final buffer = StringBuffer();
  int? previous; // Track trailing line breaks for preservation

  splitter:
  while (canIterate()) {
    var current = runeIterator.current;

    switch (current) {
      case _cr:
        {
          // If just "\r", exit immediately without overwriting trailing "\r"
          if (!canIterate()) {
            yield buffer.toString();
            buffer.clear();
            break splitter;
          }

          current = runeIterator.current;
          continue gen; // Let "lf" handle this.
        }

      gen:
      case _lf:
        {
          yield buffer.toString();
          buffer.clear();

          // In case we got this char from the carriage return
          if (current != _lf && current != -1) {
            continue writer;
          }
        }

      writer:
      default:
        buffer.writeCharCode(current);
    }

    previous = current;
  }

  /// Ensure we flush all buffered contents. A trailing line break signals
  /// we need it preserved. Thus, emit an empty string too in this case.
  if (buffer.isNotEmpty || previous == _cr || previous == _lf) {
    yield buffer.toString();
  }
}

/// Regex for `null`
final _nullRegex = RegExp(r'^(null|Null|NULL|~){1}$', multiLine: true);

/// Prefix for a `YAML` octal
const _octalPrefix = '0o';

/// Prefix for a `YAML` hexadecimal
const _hexPrefix = '0x';

/// A record represent an [int] and its `radix`
typedef _ParsedInt = ({int value, int radix});

/// Parses an [int] and returns its value and radix.
_ParsedInt? _parseInt(String normalized) {
  var radix = 10; // Defaults to 10
  var strToParse = normalized;

  void strip(String prefix) {
    strToParse = strToParse.replaceFirst(prefix, '');
  }

  if (strToParse.startsWith(_octalPrefix)) {
    strip(_octalPrefix);
    radix = 8;
  } else if (strToParse.startsWith(_hexPrefix)) {
    strip(_hexPrefix);
    radix = 16;
  }

  if (int.tryParse(strToParse, radix: radix) case int parsedInt) {
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
typedef _MaybeScalarValue<T> = _MaybeInferred<ScalarValue<T>>;

/// Value not inferred
const _notInferred = (null, null);

/// Attempts to parse the [content] as a valid `Dart` type that is not an [int]
_MaybeInferred<T> _inferDartType<T>(String content) {
  if (double.tryParse(content) case double parsedFloat) {
    return (floatTag, parsedFloat as T);
  } else if (Uri.tryParse(content) case Uri uri when uri.scheme.isNotEmpty) {
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
_MaybeScalarValue<T> _inferDartValue<T>(String content) {
  if (content.isEmpty || _nullRegex.hasMatch(content)) {
    return (nullTag, NullView(content) as ScalarValue<T>);
  } else if (_inferDartType(content) case (LocalTag dartTag, T dartType)) {
    return (dartTag, DartValue(dartType));
  }

  return _notInferred;
}

/// Infers a `YAML` [LocalTag] and a [ScalarValue] if a tag was never parsed.
({LocalTag inferredTag, ScalarValue<T> schema}) _inferSchema<T>(
  String content,
) {
  if (_parseInt(content) case (:final radix, :final value)) {
    return (
      inferredTag: integerTag,
      schema: YamlSafeInt(value, radix) as ScalarValue<T>,
    );
  } else if (_inferDartValue(content) case (
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
ScalarValue<T> _schemaFromTag<T>(String content, LocalTag parsedTag) {
  /// Lazy implementation. Instead of duplicating code, just infer the type
  /// (though not performant, we have a limited number). Represent partially
  /// as a string if the inferred tag doesn't match our parsed tag.
  if (_inferSchema<T>(content) case (
    :final inferredTag,
    :final schema,
  ) when inferredTag == parsedTag || inferredTag == stringTag) {
    return schema;
  }

  return StringView(content) as ScalarValue<T>;
}
