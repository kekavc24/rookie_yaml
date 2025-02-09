part of 'character_encoding.dart';

enum SpecialEscaped implements ReadableChar {
  /// `\0`
  unicodeNull(0x00),

  /// `\a`
  bell(0x07),

  /// `\b`
  backspace(0x08),

  /// `\v`
  verticalTab(0x0B),

  /// `\f`
  formFeed(0x0C),

  /// NEL
  nextLine(0x85),

  /// Line separator
  lineSeparator(0x2028),

  /// Paragraph separator
  paragraphSeparator(0x2029),

  /// `\e`
  asciiEscape(0x20),

  /// `\/`
  slash(0x2F),

  /// `\\`
  backSlash(0x5C),

  /// Non-breaking space
  nbsp(0xA0);

  const SpecialEscaped(this.unicode);

  @override
  final int unicode;

  @override
  String get string => String.fromCharCode(unicode);

  /// ASCII characters not represented/recognized correctly in a `Dart` string.
  static final _abstractDartStr = <String, ReadableChar>{
    '0': SpecialEscaped.unicodeNull,
    'a': SpecialEscaped.bell,
    'e': SpecialEscaped.asciiEscape,
    'N': SpecialEscaped.nextLine,
    '_': SpecialEscaped.nbsp,
    'L': SpecialEscaped.lineSeparator,
    'P': SpecialEscaped.paragraphSeparator,
    'b': SpecialEscaped.backspace,
    't': WhiteSpace.tab,
    'n': LineBreak.lineFeed,
    'v': SpecialEscaped.verticalTab,
    'f': SpecialEscaped.formFeed,
    'r': LineBreak.carriageReturn,
  };

  /// Checks and confirms if a [ReadableChar] is an escaped unicode character.
  ///
  /// Returns `true` and the number of `hex digits` such that:
  ///   - `x` - 8 bit Unicode, 2 hex digits
  ///   - `u` - 16 bit Unicode, 4 hex digits
  ///   - `U` - 32 bit Unicode, 8 hex digits
  static int checkHexWidth(ReadableChar char) {
    return switch (char.string) {
      'x' => 2,
      'u' => 4,
      'U' => 8,
      _ => 0,
    };
  }

  /// Resolves a character that cannot be represented accurately in a `Dart`
  /// string
  static ReadableChar? resolveUnrecognized(ReadableChar char) =>
      _abstractDartStr[char.string];
}
