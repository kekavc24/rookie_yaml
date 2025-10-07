import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';

/// A [StringBuffer] wrapper for buffering scalars.
final class ScalarBuffer {
  ScalarBuffer([StringBuffer? buffer]) : _buffer = buffer ?? StringBuffer();

  /// Actual buffer
  final StringBuffer _buffer;

  /// Tracks if a line break was written to this buffer
  bool _wroteLineBreak = false;

  /// Writes a single [char] to the internal [StringBuffer].
  void writeChar(int char) {
    _buffer.writeCharCode(char);
    _wroteLineBreak = _wroteLineBreak || char.isLineBreak();
  }

  /// Writes an iterable with an unknown sequence of [ReadableChar].
  ///
  /// See [writeChar].
  void writeAll(Iterable<int> chars) {
    for (final char in chars) {
      writeChar(char);
    }
  }

  /// Returns `true` if this buffer ever wrote a line break
  bool get wroteLineBreak => _wroteLineBreak;

  /// Returns whether the underlying [StringBuffer] is not empty
  bool get isNotEmpty => !isEmpty;

  /// Returns whether the underlying [StringBuffer] is empty
  bool get isEmpty => _buffer.isEmpty;

  /// Returns the length of the content
  int get length => _buffer.length;

  /// Returns the buffered string
  String bufferedContent() => _buffer.toString();

  @override
  String toString() =>
      '[ScalarBuffer]: ${_buffer.length} character(s) buffered';
}
