part of 'source_iterator.dart';

/// Byte range for a UTF-8 byte sequence. (start and end inclusive)
typedef _MinMax = (int, int);

extension UtfUtils on int {
  String readableHex() => '0x${toRadixString(16)}';
}

extension on _MinMax {
  /// Whether the [value] is within the range.
  bool hasValue(int value) => value >= $1 && value <= $2;

  /// Converts the range to "min..max".
  String toRange() => '${$1.toRadixString(16)}..${$2.toRadixString(16)}';
}

/// Default range for the third and fourth byte of a UTF-8 byte sequence. Also
/// applies to the second byte of a byte sequence which doesn't have `0xE0`,
/// `0xED`, `0xF0` and `0xF4` as its first byte.
const _uniformByteRange = (0x80, 0xBF);

/// Obtains the second byte range for the [firstByte] of a UTF-8 byte sequence.
@pragma('vm:prefer-inline')
_MinMax _unicodeSecondByteRange(int firstByte) => switch (firstByte) {
  0xE0 => (0xA0, 0xBF),
  0xED => (0x80, 0x9F),
  0xF0 => (0x90, 0xBF),
  0xF4 => (0x80, 0x8F),
  _ => _uniformByteRange,
};

/// Decodes a UTF-8 byte [source] and allows no malformed byte sequences. This
/// implementaton is based on The Unicode Standard, Version 17.0.
Iterable<int> decodeUtf8Strict(Uint8List source) sync* {
  final byteCount = source.length;
  if (byteCount == 0) return;

  const boundary = 7;

  var offset = 0;
  var canRead = true;

  /// Moves the cursor forward and returns whether more characters can be read.
  bool move() {
    ++offset;
    canRead = offset < byteCount;
    return canRead;
  }

  /// Reads the next byte if possible. Otherwise, throws.
  int takeNext(int count, int remaining) {
    if (move()) return source[offset];

    throw StateError(
      'Missing bytes in the byte sequence.\n'
      '\tCurrent offset: $offset\n'
      '\tBytes read: ${source.skip(
        max(0, offset - (count - remaining) - 1),
      ).map((e) => e.readableHex())}\n'
      '\tRemaining bytes: $remaining',
    );
  }

  /// Obtains the bits stored in the leading byte of a "n"-byte-sequence where
  /// "n" >= 1. Also returns the number of bytes ahead that should be read.
  (int count, int highs) unpack(int byte) {
    final (mask, continuation) = switch (byte >> 4) {
      15 => (boundary, 3), // 1111 0uuu & 111 -> uuu
      14 => (0xF, 2), // 1110 zzzz & 1111 -> zzzz
      _ => (0x1F, 1), //  110y yyyy & 11111 -> yyyyy
    };

    return (continuation, (byte & mask));
  }

  /// Reads the trailing bytes of a UTF-8 byte sequence.
  int readTrailingBytes(int count, int highs, int firstByte) {
    const distributed = 0x3F;
    var taken = count;

    // The second byte is the most sensitive.
    var buffer = takeNext(count, taken);
    final secondByteRange = _unicodeSecondByteRange(firstByte);

    if (!secondByteRange.hasValue(buffer)) {
      throw StateError(
        'Invalid continuation byte after the first byte.\n'
        '\tFirst byte: ${firstByte.readableHex()}\n'
        '\tSecond byte: ${buffer.readableHex()}\n'
        '\tExpected byte range: ${secondByteRange.toRange()}',
      );
    }

    buffer = (highs << 6) | (buffer & distributed);
    --taken;

    while (taken > 0) {
      final value = takeNext(count, taken);
      if (_uniformByteRange.hasValue(value)) {
        buffer = (value & distributed) | (buffer << 6);
        --taken;
        continue;
      }

      throw StateError(
        'Invalid continuation byte:\n'
        '\tCurrent byte: ${value.readableHex()}\n'
        '\tExpected byte range: ${_uniformByteRange.toRange()}',
      );
    }

    return buffer;
  }

  do {
    final byte = source[offset];

    // ASCII character.
    if (byte.bitLength <= boundary) {
      yield byte;
    } else if (byte < 0xC2 || byte > 0xF4) {
      // First byte must in the range of C2 - F4
      throw StateError(
        '${byte.readableHex()} cannot be the first byte in a UTF-8 byte'
        ' sequence.',
      );
    } else {
      final (count, highs) = unpack(byte);
      yield readTrailingBytes(count, highs, byte);
    }
  } while (move());
}

/// Allowed surrogate range.
const _surrogateRange = (0xD800, 0xDFFF);

/// Converts the [input] based on the BOM (byte order mark).
@pragma('vm:prefer-inline')
Iterable<int> _checkBOM(
  Iterable<int> input, {
  required int Function(int value) converter,
}) => input.elementAtOrNull(0) == 0xFFFE ? input.map(converter) : input;

/// Decodes a UTF-16 byte [source] after checking if a BOM is present.
Iterable<int> decodeUtf16(Iterable<int> source) => _decodeUtf16Strict(
  _checkBOM(
    source,
    converter: (codeUnit) => (((0x00FF & codeUnit) << 8) | (codeUnit >> 8)),
  ),
);

/// Decodes a UTF-16 [source]. This implementaton is based on The Unicode
/// Standard, Version 17.0.
///
/// For UTF-16 code units, surrogate pairs are combined automatically. However,
/// this function throws if any unpaired high-surrogate or low-surrogate code
/// units are present.
///
/// In all other cases, the code units must be in the range of 0x00 - 0xFFFF
/// (inclusive on both ends).
Iterable<int> _decodeUtf16Strict(Iterable<int> source) sync* {
  final iterator = source.iterator;

  /// Checks if a code unit is a trailing surrogate pair.
  bool isTrailingSurrogate(int codeUnit) => (codeUnit & 0xFC00) == 0xDC00;

  /// Reads the surrogate pairs.
  int readSurrogatePair(int high) {
    if (!iterator.moveNext()) {
      throw StateError(
        'Missing trailing low-surrogate code unit after ${high.readableHex()}.',
      );
    }

    final low = iterator.current;

    if (isTrailingSurrogate(high) || !isTrailingSurrogate(low)) {
      throw StateError(
        'Invalid surrogate pairs found in the byte source.\n'
        '\tHigh-surrogate code unit: ${high.readableHex()}\n'
        '\tLow-surrogate code unit: ${low.readableHex()}',
      );
    }

    return 0x10000 + ((high & 0x3FF) << 10) + (low & 0x3FF);
  }

  while (iterator.moveNext()) {
    final codeUnit = iterator.current;

    if (_surrogateRange.hasValue(codeUnit)) {
      yield readSurrogatePair(codeUnit);
    } else if (codeUnit < 0 || codeUnit > 0xFFFF) {
      throw StateError(
        'Invalid code unit "${codeUnit.readableHex()}" not in range of '
        '0x00 - 0xFFFF encountered.',
      );
    } else {
      yield codeUnit;
    }
  }
}

/// Decodes a 32-bit [source] as UTF-32 after checking if a BOM is present.
Iterable<int> decodeUtf32(Uint32List source) => _decodeUtf32Strict(
  _checkBOM(
    source,
    converter: (codeUnit) =>
        ((0xFF & codeUnit) << 24) |
        ((0xFF00 & codeUnit) << 8) |
        ((codeUnit >> 8) & 0xFF00) |
        (codeUnit >> 24),
  ),
);

/// Decodes a UTF-32 [source]. This implementaton is based on The Unicode
/// Standard, Version 17.0.
///
/// Any surrogate code units are considered ill-formed. In all other cases,
/// the code units must be in the range of 0x00 - 0x10FFFF.
Iterable<int> _decodeUtf32Strict(Iterable<int> source) sync* {
  bool notInRange(int value) => value < 0 || value > 0x10FFFF;

  for (final codeUnit in source) {
    if (notInRange(codeUnit)) {
      throw StateError(
        'Invalid code unit "${codeUnit.readableHex()}" not in range of '
        '0x00 - 0x10FFFF encountered.',
      );
    } else if (_surrogateRange.hasValue(codeUnit)) {
      throw StateError(
        'Ill-formed surrogate code unit "${codeUnit.readableHex()}" not allowed'
        'in UTF-32.',
      );
    }

    yield codeUnit;
  }
}
