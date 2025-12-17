part of 'source_iterator.dart';

/// ASCII characters not represented/recognized correctly in a `Dart` string.
/// This is (..maybe?..) great if we also get raw strings as input.
final _abstractDartStr = <int, int>{
  0x30: unicodeNull, // 0
  0x61: bell, // a
  0x65: asciiEscape, // e
  0x4E: nextLine, // N
  0x5F: nbsp, // _
  0x4C: lineSeparator, // L
  0x50: paragraphSeparator, // P
  0x62: backspace, // b
  0x74: tab, // t
  0x6E: lineFeed, // n
  0x76: verticalTab, // v
  0x66: formFeed, // f
  0x72: carriageReturn, // r
};

const _utf8Marker = 0x78;
const _utf16Marker = 0x75;
const _utf32Marker = 0x55;

/// Returns the number of hex digits represent by the escaped unicode.
///   - `x` - 8 bit Unicode, 2 hex digits
///   - `u` - 16 bit Unicode, 4 hex digits
///   - `U` - 32 bit Unicode, 8 hex digits
///
/// Returns `null` otherwise.
int? checkHexWidth(int unicode) => switch (unicode) {
  _utf8Marker => 2,
  _utf16Marker => 4,
  _utf32Marker => 8,
  _ => null,
};

/// Resolves an escaped character in a double quoted string to its unescaped
/// form in unicode
int? resolveDoubleQuotedEscaped(int unicode) {
  if (unicode case backSlash || slash || space || tab || doubleQuote) {
    return unicode;
  }

  return _abstractDartStr[unicode];
}

extension Flattened on int? {
  /// Converts the UTF char to string if not null.
  String asString() => this == null ? '<null>' : String.fromCharCode(this!);

  /// Whether `null` or [matcher] is `true`.
  bool isNullOr(bool Function(int value) matcher) =>
      this == null || matcher(this!);

  /// Whether not `null` and [matcher] is `true`.
  bool isNotNullAnd(bool Function(int value) matcher) =>
      this != null && matcher(this!);
}

extension SpacingUtils on int {
  /// Returns `true` if current unicode is a space
  bool isIndent() => this == space;

  /// Returns true if the unicode is space or a `\t`
  bool isWhiteSpace() => isIndent() || this == tab;

  /// Returns true if the unicode is `\n` or `\r`
  bool isLineBreak() => this == lineFeed || this == carriageReturn;
}

const capA = 0x41;
const capF = 0x46;
const _capZ = 0x5A;

const lowerA = 0x61;
const _lowerF = 0x66;
const _lowerZ = 0x7A;

/// Hex value of `0` in ASCII
const asciiZero = 0x30;
const asciiNine = 0x39;

const _lowerPrintableAscii = 0x20;
const _upperPrintableAscii = 0x7E;

const _lowerBMP = 0xA0;
const _upperBMP = 0xD7FF;

const _lowerAdditionalSet = 0xE000;
const _upperAdditionalSet = 0xFFFD;

const _lowerSupplementalPlane = 0x010000;
const _upperSupplementalPlane = 0x10FFFF;

extension CharUtils on int {
  /// Checks if digit. `0x30 - 0x39`
  bool isDigit() => this >= asciiZero && this <= asciiNine;

  /// Checks if hex digit.
  ///   - Valid digit `0x30 - 0x39`
  ///   - `A - F`
  ///   - `a - f`
  bool isHexDigit() =>
      isDigit() ||
      (this >= capA && this <= capF) ||
      (this >= lowerA && this <= _lowerF);

  /// Checks if valid ASCII letter, that is, alphabetic.
  bool isAsciiLetter() =>
      (this >= capA && this <= _capZ) || (this >= lowerA && this <= _lowerZ);

  /// Checks if alphanumeric or word
  bool isAlphaNumeric() =>
      isDigit() || isAsciiLetter() || this == blockSequenceEntry;

  /// Checks if printable
  bool isPrintable() =>
      this == tab ||
      this == lineFeed ||
      this == carriageReturn ||
      this == nextLine ||
      (this >= _lowerPrintableAscii && this <= _upperPrintableAscii) ||
      (this >= _lowerBMP && this <= _upperBMP) ||
      (this >= _lowerAdditionalSet && this <= _upperAdditionalSet) ||
      (this >= _lowerSupplementalPlane && this <= _upperSupplementalPlane);

  /// Delimiters denoting a flow collection context. `{`  `}`  `[`  `]`  `,`
  bool isFlowDelimiter() =>
      this == mappingStart ||
      this == mappingEnd ||
      this == flowSequenceStart ||
      this == flowSequenceEnd ||
      this == flowEntryEnd;

  /// Return `true` only if the character is printable and not:
  ///   - A whitespace character
  ///   - Line break i.e. `\r` or `\n`
  bool isNonSpaceChar() => !isWhiteSpace() && !isLineBreak() && isPrintable();
}

/// Characters allowed in a `URI` not included in `isAlphaNumeric` or
/// `isHexDigit` or `isFlowDelimiter`
const _miscUriChars = <int>{
  comment, // #
  0x3B, // ;
  slash, // /
  mappingKey, // ?
  mappingValue, // :
  reservedAtSign, // @
  anchor, // &
  0x3D, // =
  0x2B, // +
  0x24, // $
  flowEntryEnd, // ,
  0x5F, // _
  0x2E, // .
  tag, // !
  0xFE, // ~
  alias, // *
  singleQuote, // '
  0x28, // (
  0x29, // )
  flowSequenceStart, // [
  flowSequenceEnd, // ]
};

/// Checks with bias if [uriChar] is a valid character.
///
/// The bias comes in when non-escaped characters, that is, characters not
/// in `hex` form (`.%[0-9A-Fa-f]{2}`), must pass in a single character in
/// [uriChar].
///
/// Escaped `hex` characters must pass in `List<int>`.
bool isUriChar<T>(T uriChar) {
  if (uriChar is int) {
    return _isValidSingleUriChar(uriChar);
  }

  assert(uriChar is Iterable<int>, 'Expected list of unicode integers');
  return _isValidHexInUri(uriChar as Iterable<int>);
}

/// Checks if a single [unicode] is a valid [Uri] character
bool _isValidSingleUriChar(int unicode) =>
    unicode.isAlphaNumeric() ||
    _miscUriChars.contains(unicode);

/// Checks if a sequence of escaped `hex` characters are valid
bool _isValidHexInUri(Iterable<int> chars) {
  return chars.length == 3 &&
      chars.first == directive &&
      chars.skip(1).every((c) => c.isHexDigit());
}
