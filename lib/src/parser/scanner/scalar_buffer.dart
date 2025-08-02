import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';

/// A [StringBuffer] wrapper for buffering scalars.
final class ScalarBuffer {
  ScalarBuffer({required this.ensureIsSafe, StringBuffer? buffer})
    : _buffer = buffer ?? StringBuffer();

  /// Tracks the lines within a formatted scalar
  final _contentByLine = <String>[];

  /// Ensures the [ReadableChar] is printable before writing
  final bool ensureIsSafe;

  /// Actual buffer
  final StringBuffer _buffer;

  /// Saves the current [_buffer] state as a complete line
  void _flushBuffer() {
    _contentByLine.add(_buffer.toString());
    _buffer.clear();
  }

  /// Writes a single [char] to the internal [StringBuffer].
  void writeChar(ReadableChar char) {
    if (char is LineBreak) {
      return _flushBuffer();
    }

    _buffer.write(ensureIsSafe ? char.raw() : char.string);
  }

  /// Writes an iterable with an unknown sequence of [ReadableChar].
  ///
  /// See [writeChar].
  void writeAll(Iterable<ReadableChar> chars, {bool anyIsLineBreak = false}) {
    for (final char in chars) {
      writeChar(char);
    }
  }

  /// Returns whether the underlying [StringBuffer] is not empty
  bool get isNotEmpty => !isEmpty;

  /// Returns whether the underlying [StringBuffer] is empty
  bool get isEmpty => _buffer.isEmpty;

  /// Returns the length of the content
  int get length => _buffer.length;

  /// Returns the lines in the formatted scalar.
  ///
  /// `NOTE:` This method should only be called once the scalar has been
  /// parsed completely. By default, it assumes the last content buffered
  /// once called is a separate line.
  Iterable<String> viewAsLines() {
    if (_buffer.isNotEmpty) {
      _flushBuffer();
    }

    return _contentByLine;
  }

  @override
  String toString() =>
      '[ScalarBuffer]: ${_buffer.length} character(s) buffered';
}
