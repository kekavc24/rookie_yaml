import 'dart:math';

import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'ambigous_delegate.dart';
part 'int_delegate.dart';

/// A scalar whose content has been buffered (efficiently) in one pass and
/// its associated YAML schema tag.
typedef BufferedScalar<T> = ({TagShorthand schemaTag, ScalarValue<T> scalar});

/// A delegate that buffers a scalar's content directly from the
/// [SourceIterator].
sealed class ScalarValueDelegate<T> extends BytesToScalar<BufferedScalar<T>> {
  var _isClosed = false;
  var _wroteLineBreak = false;

  /// Writes the utf [codePoint] to the scalar's underlying buffer.
  void writeCharCode(int codePoint);

  @override
  CharWriter get onWriteRequest => writeCharCode;

  /// Whether the underlying buffer's content has a line break.
  bool get bufferedLineBreak => _wroteLineBreak;

  @override
  void onComplete() {
    if (_isClosed) {
      throw StateError(
        '$runtimeType: [onWriteRequest] was called after this buffer was'
        ' closed',
      );
    }

    _isClosed = true;
  }
}

/// A generic string buffer that uses a [StringBuffer] under the hood.
base class _FallbackBuffer extends ScalarValueDelegate<String> {
  _FallbackBuffer([String? content]) : _buffer = StringBuffer(content ?? '');

  /// Buffer for the string.
  final StringBuffer _buffer;

  @override
  BufferedScalar<String> parsed() => (
    schemaTag: stringTag,
    scalar: DartValue(_buffer.toString()),
  );

  @override
  void writeCharCode(int codePoint) {
    _wroteLineBreak = _wroteLineBreak || codePoint.isLineBreak();
    _buffer.writeCharCode(codePoint);
  }
}

/// A generic string buffer whose initial state is always empty.
final class StringDelegate extends _FallbackBuffer {}

base class _LazyTypeFromString<L> extends ScalarValueDelegate<Object?> {
  _LazyTypeFromString({required this.onParsed});

  /// Underlying string buffer.
  final _delegate = StringDelegate();

  /// Custom type if string is
  final BufferedScalar<L>? Function(String content) onParsed;

  @override
  bool get bufferedLineBreak => _delegate._wroteLineBreak;

  @override
  void writeCharCode(int codePoint) => _delegate.writeCharCode(codePoint);

  @override
  BufferedScalar<Object?> parsed() {
    final string = _delegate.parsed();
    return _wroteLineBreak ? string : onParsed(string.scalar.value) ?? string;
  }
}

/// A delegate that infers a null from a string.
final class NullDelegate extends _LazyTypeFromString<String?> {
  NullDelegate()
    : super(
        onParsed: (content) => switch (content) {
          'null' ||
          'Null' ||
          'NULL' ||
          '~' => (schemaTag: nullTag, scalar: NullView(content)),
          _ => null,
        },
      );
}

/// A delegate that infers a [bool] from a string.
final class BoolDelegate extends _LazyTypeFromString<bool> {
  BoolDelegate()
    : super(
        onParsed: (content) => switch (content) {
          'true' ||
          'True' ||
          'TRUE' => (schemaTag: booleanTag, scalar: DartValue(true)),
          'false' ||
          'False' ||
          'FALSE' => (schemaTag: booleanTag, scalar: DartValue(false)),
          _ => null,
        },
      );
}

/// A delegate that infers a [double] from a string.
final class FloatDelegate extends _LazyTypeFromString<double> {
  FloatDelegate()
    : super(
        onParsed: (content) => switch (double.tryParse(content)) {
          double value => (schemaTag: floatTag, scalar: DartValue(value)),
          _ => null,
        },
      );
}

/// A callback for delegates that can reset to their initial state.
///
/// [charOnRecover] represents the character that force the delegate to
/// terminate its parsing state.
///
/// [content] represents the delegate's state before [charOnRecover] was
/// encountered.
typedef _RecoverFunction = void Function(String content, int charOnRecover);

/// A buffer that can infer a type or default to a string if the type could not
/// be inferred.
sealed class RecoverableDelegate extends ScalarValueDelegate<Object> {
  RecoverableDelegate._(this._buffer);

  /// The current buffer that is accepting utf code points. Most subclasses
  /// may call [_recover] when a code point could not be converted to the
  /// desired type.
  ScalarValueDelegate<Object> _buffer;

  /// Creates a [RecoverableDelegate] that parses integers.
  factory RecoverableDelegate.forInt() => _RecoverableImpl(_IntegerDelegate());

  /// Resets the underlying [_buffer] to a generic string buffer with its
  /// initial state being the [content] already buffered by `this`.
  /// [charOnRecovery] represents the code point that `this` rejected before
  /// calling [_recover].
  void _recover(String content, int charOnRecovery) {
    _buffer = _FallbackBuffer(content.toString())
      ..writeCharCode(charOnRecovery);
  }

  @override
  bool get bufferedLineBreak => _buffer._wroteLineBreak;

  @override
  void writeCharCode(int codePoint) => _buffer.writeCharCode(codePoint);

  @override
  void onComplete() {
    _buffer.onComplete();
    super.onComplete();
  }

  @override
  BufferedScalar<Object> parsed() => _buffer.parsed();
}

/// Helper for [ScalarValueDelegate] implementations that can support efficient
/// recovery to their initial state.
base mixin _Recoverable on ScalarValueDelegate<Object> {
  /// Callback that helps `this` recover if its object could not be parsed.
  late final _RecoverFunction _recover;
}

/// A [RecoverableDelegate] implementation that wraps a delegate marked as
/// [_Recoverable].
final class _RecoverableImpl extends RecoverableDelegate {
  _RecoverableImpl(_Recoverable delegate) : super._(delegate) {
    delegate._recover = _recover;
  }
}
