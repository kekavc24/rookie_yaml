part of 'directives.dart';

const _equality = DeepCollectionEquality();

/// Represents any unknown directive which `YAML`, by default, reserves for
/// future use. Typically any that is not a [YamlDirective] or a [GlobalTag].
///
/// {@category yaml_docs}
sealed class ReservedDirective implements Directive {
  ReservedDirective({required this.name, required Iterable<String> parameters})
    : parameters = List.from(parameters, growable: false);

  @override
  final String name;

  @override
  final List<String> parameters;

  @override
  bool operator ==(Object other) =>
      other is ReservedDirective &&
      other.name == name &&
      _equality.equals(other.parameters, parameters);

  @override
  int get hashCode => _equality.hash([name, parameters]);

  @override
  String toString() => _dumpDirective(this);
}

final class _ReservedImpl extends ReservedDirective {
  _ReservedImpl({required super.name, required super.parameters});
}

/// Parses a [ReservedDirective]
ReservedDirective _parseReservedDirective(
  String name, {
  required SourceIterator iterator,
}) {
  final params = <String>[];
  final buffer = StringBuffer();

  void flushBuffer() {
    if (buffer.isNotEmpty) {
      params.add(buffer.toString());
      buffer.clear();
    }
  }

  /// Reserved directives are prone to endless grouped token consumption between
  /// with whitespace. YAML allows comments in directives (tricky). The
  /// condition below may seem unorthodox. It's simple.
  /// Exit if:
  ///   1. If we have no more tokens and the char at cursor is not null
  ///   2. If (1) stands, capture the non-null [current] and check if we reached
  ///      the end of the line.
  ///   3. If (2) stands (we never reached the end of the line), check if the
  ///      captured non-null [current] is a comment only if the char before was
  ///      non-null and a separation space (tab/space).
  while (!iterator.isEOF &&
      !iterator.current.isLineBreak() &&
      !(iterator.current == comment &&
          iterator.before.isNotNullAnd((c) => c.isWhiteSpace()))) {
    // Skip separation lines (include tabs). Save current parameter.
    if (iterator.current case space || tab) {
      skipWhitespace(iterator, skipTabs: true);
      flushBuffer();
    } else if (iterator.current.isPrintable()) {
      buffer.writeCharCode(iterator.current);
    } else {
      throwWithSingleOffset(
        iterator,
        message:
            'Only printable characters are allowed in a directive '
            'parameter',
        offset: iterator.currentLineInfo.current,
      );
    }

    iterator.nextChar();
  }

  flushBuffer(); // Just incase
  return _ReservedImpl(name: name, parameters: params);
}
