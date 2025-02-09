part of 'character_encoding.dart';

const _capA = 0x41;
const _capF = 0x46;
const _capZ = 0x5A;

const _lowerA = 0x61;
const _lowerF = 0x66;
const _lowerZ = 0x7A;

/// Checks if digit. `0x30 - 0x39`
bool isDigit(ReadableChar char) {
  final unicode = char.unicode;
  return unicode >= 0x30 && unicode <= 0x39;
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
