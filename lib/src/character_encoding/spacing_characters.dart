part of 'character_encoding.dart';

/// Line breaking characters
enum LineBreak implements ReadableChar {
  /// `\n`
  lineFeed(0x0A),

  /// `\r`
  carriageReturn(0x0D);

  const LineBreak(this.unicode);

  @override
  final int unicode;

  @override
  String get string => String.fromCharCode(unicode);

  /// `\r\n`
  static String get crlf => '${LineBreak.carriageReturn.string}$lf';

  /// `\n`
  static String get lf => LineBreak.lineFeed.string;

  @override
  String raw() => string;
}

/// White space characters
enum WhiteSpace implements ReadableChar {
  /// \t
  tab(0x09),

  /// Normal whitespace
  space(0x20);

  const WhiteSpace(this.unicode);

  @override
  final int unicode;

  @override
  String get string => String.fromCharCode(unicode);

  @override
  String raw() => string;
}
