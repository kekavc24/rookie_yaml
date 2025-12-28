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

  bool stopParsingDirective() {
    // Reserved directives are prone to endless grouped token consumption
    // separated by whitespace. YAML allows comments in directives (tricky).
    // Exit:
    //   1. If we have no more tokens.
    //   2. If we reached the end of the line.
    //   3. If it's a possible comment. The comment will be read until a line
    //      break is seen.
    return iterator.isEOF ||
        iterator.current.matches(
          (current) =>
              current.isLineBreak() ||
              (current == comment &&
                  iterator.before.isNotNullAnd((c) => c.isWhiteSpace())),
        );
  }

  while (!stopParsingDirective()) {
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
