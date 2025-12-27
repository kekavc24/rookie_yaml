part of 'efficient_scalar_delegate.dart';

/// An eager "first-on-match" delegate which inspects the first character
/// from a scalar's content and assigns another [ScalarValueDelegate] delegate
/// to handle the next characters it will receive.
final class AmbigousDelegate extends ScalarValueDelegate<Object?> {
  AmbigousDelegate({required this.defaultToString}) {
    _ambigousWriter = _checkTypeLoose;
  }

  /// Whether this delegate should return a string.
  final bool defaultToString;

  /// A lazy function that performs the underlying writes.
  late Function(int char) _ambigousWriter;

  /// The actual object this delegate attempts to quickly hand off writes to.
  ScalarValueDelegate<Object?>? _scalar;

  @override
  BufferedScalar<Object?> parsed() {
    if (defaultToString) {
      return _scalar?.parsed() ?? (schemaTag: stringTag, scalar: DartValue(''));
    } else if (_scalar case _FallbackBuffer(
      :final _buffer,
      :final _wroteLineBreak,
    ) when !_wroteLineBreak) {
      return _intOrDouble(_buffer);
    }

    return _scalar?.parsed() ?? (schemaTag: nullTag, scalar: NullView(''));
  }

  @override
  bool get bufferedLineBreak => _scalar?.bufferedLineBreak ?? false;

  @override
  void writeCharCode(int codePoint) => _ambigousWriter(codePoint);

  /// Matches the first [char] to a delegate that returns a type.
  ///
  /// It should be noted that this method is always called once when the
  /// first utf code point arrives. Successive writes will be handled by the
  /// [_scalar] itself. If the first [char] never arrives, nothing happens.
  void _checkTypeLoose(int char) {
    if (defaultToString) {
      _scalar = StringDelegate();
    } else {
      // We can eagerly and loosely attempt to determine the type depending on
      // the first code point we get. Consider this a "first-on-match" regex. We
      // intentionally do not match for integers and floats.
      _scalar = switch (char) {
        // f, F in "false" or "False". t, T in "true" or "True"
        capF || lowerF || 0x54 || 0x74 => BoolDelegate(),

        // n, N in "null" or "Null" or "NULL". "~" tilde.
        0x4E || 0x6E || 0x7E => NullDelegate(),
        _ => _FallbackBuffer(),
      };
    }

    _ambigousWriter = _scalar!.writeCharCode;
    _ambigousWriter(char);
  }
}

/// Attempts to infer [int] or [double] from the content in the [buffer].
BufferedScalar<Object> _intOrDouble(StringBuffer buffer) {
  final content = buffer.toString();

  if (_parseInt(content) case _ParsedInt(:final value, :final radix)) {
    return (schemaTag: integerTag, scalar: YamlSafeInt(value, radix));
  } else if (double.tryParse(content) case double float) {
    return (schemaTag: floatTag, scalar: DartValue(float));
  }

  return (schemaTag: stringTag, scalar: DartValue(content));
}

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
