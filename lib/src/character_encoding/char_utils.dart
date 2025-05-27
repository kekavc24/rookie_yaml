part of 'character_encoding.dart';

const _capA = 0x41;
const _capF = 0x46;
const _capZ = 0x5A;

const _lowerA = 0x61;
const _lowerF = 0x66;
const _lowerZ = 0x7A;

/// Hex value of `0` in ASCII
const asciiZero = 0x30;
const _asciiNine = 0x39;

/// Checks if digit. `0x30 - 0x39`
bool isDigit(ReadableChar char) {
  final unicode = char.unicode;
  return unicode >= asciiZero && unicode <= _asciiNine;
}

/// Checks if hex digit.
///   - Valid digit `0x30 - 0x39`
///   - `A - F`
///   - `a - f`
bool isHexDigit(ReadableChar char) {
  final unicode = char.unicode;
  return isDigit(char) ||
      (unicode >= _capA && unicode <= _capF) ||
      (unicode >= _lowerA && unicode <= _lowerF);
}

/// Checks if valid ASCII letter, that is, alphabetic.
bool isAsciiLetter(ReadableChar char) {
  final unicode = char.unicode;
  return (unicode >= _capA && unicode <= _capZ) ||
      (unicode >= _lowerA && unicode <= _lowerZ);
}

/// Checks if alphanumeric or word
bool isAlphaNumeric(ReadableChar char) =>
    isDigit(char) ||
    isAsciiLetter(char) ||
    char.unicode == Indicator.blockSequenceEntry.unicode;

const _lowerPrintableAscii = 0x20;
const _upperPrintableAscii = 0x7E;

const _lowerBMP = 0xA0;
const _upperBMP = 0xD7FF;

const _lowerAdditionalSet = 0xE000;
const _upperAdditionalSet = 0xFFFD;

const _lowerSupplementalPlane = 0x010000;
const _upperSupplementalPlane = 0x10FFFF;

/// Checks if printable
bool isPrintable(ReadableChar char) {
  final unicode = char.unicode;

  return char == WhiteSpace.tab ||
      char == LineBreak.lineFeed ||
      char == LineBreak.carriageReturn ||
      char == SpecialEscaped.nextLine ||
      (unicode >= _lowerPrintableAscii && unicode <= _upperPrintableAscii) ||
      (unicode >= _lowerBMP && unicode <= _upperBMP) ||
      (unicode >= _lowerAdditionalSet && unicode <= _upperAdditionalSet) ||
      (unicode >= _lowerSupplementalPlane &&
          unicode <= _upperSupplementalPlane);
}

/// Delimiters denoting a flow context. `{`  `}`  `[`  `]`  `,`
final flowDelimiters = <Indicator>{
  Indicator.mappingStart,
  Indicator.mappingEnd,
  Indicator.flowSequenceStart,
  Indicator.flowSequenceEnd,
  Indicator.flowEntryEnd,
};

/// Characters allowed in a `URI` not included in [isAlphaNumeric] or
/// [flowDelimiters] or [isHexDigit]
final _miscUriChars = <int>{
  Indicator.comment.unicode, // #
  0x3B, // ;
  SpecialEscaped.slash.unicode, // /
  Indicator.mappingKey.unicode, // ?
  Indicator.mappingValue.unicode, // :
  Indicator.reservedAtSign.unicode, // @
  Indicator.anchor.unicode, // &
  0x3D, // =
  0x2B, // +
  0x24, // $
  0x5F, // _
  0x2E, // .
  Indicator.tag.unicode, // !
  0xFE, // ~
  Indicator.alias.unicode, // *
  Indicator.singleQuote.unicode, // '
};

/// Checks with bias if [uriChar] is a valid character.
///
/// The bias comes in when non-escaped characters, that is, characters not
/// in `hex` form (`.%[0-9A-Fa-f]{2}`), must pass in a single character in
/// [uriChar].
///
/// Escaped `hex` characters must pass in `List<ReadableChar>`.
bool isUriChar<T>(T uriChar) {
  if (T == ReadableChar) {
    return _isValidSingleUriChar(uriChar as ReadableChar);
  }

  assert(uriChar is List<ReadableChar>, 'Expected list of "ReadableChar"');
  return _isValidHexInUri(uriChar as List<ReadableChar>);
}

/// Checks if a single [ReadableChar] is a valid [Uri] character
bool _isValidSingleUriChar(ReadableChar char) {
  return flowDelimiters.contains(char) ||
      isAlphaNumeric(char) ||
      _miscUriChars.contains(char.unicode);
}

/// Checks if a sequence of escaped `hex` characters are valid
bool _isValidHexInUri(List<ReadableChar> chars) {
  return chars.length == 3 &&
      chars
          .whereNot((char) => char == Indicator.directive || isHexDigit(char))
          .isEmpty;
}

enum YamlContext {
  /// Within a block style context
  blockIN,

  /// Outside a block style context
  blockOUT,

  /// Within a block key context.
  blockKEY,

  /// Within a flow style context
  flowIN,

  /// Outside a flow style context
  flowOUT,

  /// Within a flow key context
  flowKEY,
}
