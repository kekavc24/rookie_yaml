part of 'efficient_scalar_delegate.dart';

const _positive = 0x2B;
const _negative = blockSequenceEntry;

const _octalId = 0x6F;
const _hexId = 0x78;

/// A delegate that parses any hex, octal or integer and recovers as a string
/// if the [int] could not be parsed. This delegate only parses integers
/// annotated with `!!int`.
final class _IntegerDelegate extends ScalarValueDelegate<Object>
    with _Recoverable {
  _IntegerDelegate() {
    _intParser = _signParser;
  }

  /// Current step in the integer parsing stage.
  late void Function(int codePoint) _intParser;

  /// Whether an integer was ever parsed.
  var _parsedInt = false;

  /// Number of zeros just before the actual number starts.
  var _paddingLeft = 0;

  /// Positive/negative number.
  int? _sign;

  /// Radix for the integer. Defaults to base 10.
  int? _radix;

  /// Whether the integer can be parsed as any radix other than base 10.
  bool get _hasNoRadix => _paddingLeft == 1 && _radix == null;

  /// Whether the integer is valid.
  bool get _isValidInt => _parsedInt || (_paddingLeft >= 1);

  /// Integer being parsed
  var _value = 0;

  @override
  void writeCharCode(int codePoint) => _intParser(codePoint);

  @override
  void onComplete() {
    if (_isValidInt && _sign != null) {
      _value = _sign! * _value;
    }

    super.onComplete();
  }

  @override
  BufferedScalar<Object> parsed() {
    return _isValidInt
        ? (schemaTag: integerTag, scalar: YamlSafeInt(_value, _radix ?? 10))
        : (
            schemaTag: stringTag,
            scalar: DartValue(_recoverAsRadix(_radix ?? 10)),
          );
  }

  /// Recovers the [_value] parsed so far as the specified [radix].
  String _recoverAsRadix(int radix) {
    final padding =
        '0' * max(_radix != 10 ? _paddingLeft - 1 : _paddingLeft, 0);

    return switch (radix) {
      16 => '0x$padding${_parsedInt ? _value.toRadixString(16) : ''}',
      8 => '0o$padding${_parsedInt ? _value.toRadixString(8) : ''}',
      _ =>
        '${_sign == null
                ? ''
                : _sign! > 0
                ? '+'
                : '-'}'
            '$padding${_parsedInt ? _value : ''}',
    };
  }

  /// Recovers the [_value] parsed so far as a base 10 integer.
  void _recoverBase10(int current) => _recover(_recoverAsRadix(10), current);

  /// Parses the sign of the integer if present. This serves as the base
  /// disambiguation point for the integer.
  void _signParser(int char) {
    switch (char) {
      case _positive:
        _markAsSigned(positive: true);

      case _negative:
        _markAsSigned(positive: false);

      case asciiZero:
        {
          _intParser = _skipPadding;
          _skipPadding(char);
        }

      default:
        {
          if (char.isDigit()) {
            _radix = 10;
            _intParser = _parseBase10;
            _parseBase10(char);
            break;
          }

          _recover('', char); // Nothing parsed so far
        }
    }
  }

  /// Marks the integer's sign and defaults to base 10.
  void _markAsSigned({required bool positive}) {
    _sign = positive ? 1 : -1;
    _radix = 10;
    _intParser = _skipPadding;
  }

  /// Skips the leading zeros of an integer and attempts to determine if the
  /// integer is an hex or octal.
  void _skipPadding(int char) {
    switch (char) {
      case asciiZero:
        {
          ++_paddingLeft;
          _radix ??= _paddingLeft > 1 ? 10 : null;
        }

      // 0o
      case _octalId when _hasNoRadix:
        _radix = 8;

      // 0x
      case _hexId when _hasNoRadix:
        _radix = 16;

      default:
        _assignBase(char);
    }
  }

  /// Initiates the parsing of the integer from a non-zero value.
  void _assignBase(int char) {
    _parsedInt = _paddingLeft > 1;

    switch (_radix) {
      case 16:
        {
          _intParser = _parseBase16;
          _parseBase16(char);
        }

      case 8:
        {
          _intParser = _parseBase8;
          _parseBase8(char);
        }

      default:
        _parsedInt = true;
        _intParser = _parseBase10;
        _parseBase10(char);
    }
  }

  /// Parses the [char] as a base 10 integer code point.
  void _parseBase10(int char) {
    if (!char.isDigit()) {
      _recoverBase10(char);
      return;
    }

    _parsedInt = _parsedInt || true; // Any benefit?
    _value = (_value * 10) + (char - asciiZero);
  }

  /// Parses the [char] as a base 16 integer code point.
  void _parseBase16(int char) {
    if (!char.isHexDigit()) {
      _recover(_recoverAsRadix(16), char);
      return;
    }

    _parsedInt = _parsedInt || true; // Any benefit?
    _value =
        (_value << 4) |
        (char > asciiNine
            ? (10 + (char - (char > capF ? lowerA : capA)))
            : (char - asciiZero));
  }

  /// Parses the [char] as a base 8 integer code point.
  void _parseBase8(int char) {
    if (char < asciiZero || char > 0x37) {
      _recover(_recoverAsRadix(8), char);
      return;
    }

    _parsedInt = _parsedInt || true; // Any benefit?
    _value = (_value << 3) | (char - asciiZero);
  }
}
