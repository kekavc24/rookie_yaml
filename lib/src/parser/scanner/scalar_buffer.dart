import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';

/// A mixin abstraction that mimics the [StringBuffer] class but writes
/// [ReadableChar].
abstract mixin class _ScalarBufferMixin {
  /// Writes a single [char] to the internal [StringBuffer].
  void writeChar(ReadableChar char);

  /// Writes an iterable with an unknown sequence of [ReadableChar].
  ///
  /// See [writeChar].
  void writeAll(Iterable<ReadableChar> chars, {bool anyIsLineBreak = false}) {
    for (final char in chars) {
      writeChar(char);
    }
  }

  /// Returns `true` if a [LineBreak] was buffered. Otherwise, `false`.
  bool get hasLineBreaks;

  /// Returns whether the underlying [StringBuffer] is empty
  bool get isEmpty;

  /// Returns whether the underlying [StringBuffer] is not empty
  bool get isNotEmpty => !isEmpty;

  /// Returns the length of the content
  int get length;

  /// Returns the contents of the internal [StringBuffer] used to buffer the
  /// [ReadableChar]
  String bufferedString();
}

/// A [StringBuffer] wrapper for buffering scalars.
base class ScalarBuffer with _ScalarBufferMixin {
  ScalarBuffer({required bool ensureIsSafe, StringBuffer? buffer})
    : _buffer = _UnfinalizedBuffer(ensureIsSafe: ensureIsSafe, buffer: buffer);

  final _UnfinalizedBuffer _buffer;

  @override
  String bufferedString() => _buffer.bufferedString();

  @override
  bool get hasLineBreaks => _buffer.hasLineBreaks;

  @override
  void writeChar(ReadableChar char) => _buffer._finalized.writeChar(char);

  @override
  bool get isEmpty => _buffer.isEmpty;

  @override
  int get length => _buffer.length;

  @override
  String toString() => _buffer.toString();
}

/// A buffer that doesn't need to check if a character being written to it
/// is a line break.
base class FinalizedScalarBuffer with _ScalarBufferMixin {
  FinalizedScalarBuffer({required this.ensureIsSafe, StringBuffer? buffer})
    : _buffer = buffer ?? StringBuffer();

  /// Ensures the [ReadableChar] is printable before writing
  final bool ensureIsSafe;

  /// Actual buffer
  final StringBuffer _buffer;

  /// Tracks if a line break was written.
  bool _wroteLineBreak = false;

  @override
  void writeChar(ReadableChar char) =>
      ensureIsSafe ? safeWriteChar(_buffer, char) : _buffer.write(char.string);

  @override
  bool get hasLineBreaks => _wroteLineBreak;

  @override
  bool get isEmpty => _buffer.isEmpty;

  @override
  int get length => _buffer.length;

  @override
  String bufferedString() => _buffer.toString();

  @override
  String toString() =>
      '[ScalarBuffer]: ${_buffer.length} character(s) buffered';
}

/// A custom wrapper buffer that switches to a [FinalizedBuffer] after
/// encountering its first line break.
///
/// A utility class for [ScalarBuffer]
final class _UnfinalizedBuffer extends FinalizedScalarBuffer {
  _UnfinalizedBuffer({required super.ensureIsSafe, super.buffer}) {
    _finalized = this;
  }

  ///
  late FinalizedScalarBuffer _finalized;

  @override
  void writeChar(ReadableChar char) {
    // Attempt to finalize early
    if (char is LineBreak) {
      _finalized = FinalizedScalarBuffer(
        ensureIsSafe: ensureIsSafe,
        buffer: _buffer,
      ).._wroteLineBreak = true;
      _finalized.writeChar(char);
      return;
    }

    super.writeChar(char);
  }
}
