import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';

/// A [StringBuffer] wrapper for buffering scalars.
final class ScalarBuffer {
  ScalarBuffer({required this.ensureIsSafe, StringBuffer? buffer})
    : _buffer = buffer ?? StringBuffer();

  /// Ensures the [ReadableChar] is printable before writing
  final bool ensureIsSafe;

  /// Actual buffer
  final StringBuffer _buffer;

  /// Tracks if a line break was written to this buffer
  bool _wroteLineBreak = false;

  /// Writes a single [char] to the internal [StringBuffer].
  void writeChar(ReadableChar char) {
    _buffer.write(ensureIsSafe ? char.raw() : char.string);
    _wroteLineBreak = _wroteLineBreak || char is LineBreak;
  }

  /// Writes an iterable with an unknown sequence of [ReadableChar].
  ///
  /// See [writeChar].
  void writeAll(Iterable<ReadableChar> chars) {
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
