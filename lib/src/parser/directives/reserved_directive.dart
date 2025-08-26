part of 'directives.dart';

const _equality = DeepCollectionEquality();

/// Represents any unknown directive which `YAML`, by default, reserves for
/// future use. Typically any that is not a [YamlDirective] or a [GlobalTag].
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
  required GraphemeScanner scanner,
}) {
  final params = <String>[];
  final buffer = StringBuffer();

  void flushBuffer() {
    if (buffer.isNotEmpty) {
      params.add(buffer.toString());
      buffer.clear();
    }
  }

  var current = scanner.charAtCursor;

  // TODO: Include comments in directive
  while (scanner.canChunkMore &&
      current.isNotNullAnd((c) => !c.isLineBreak())) {
    // Intentional switch case use!
    switch (current) {
      /// Skip separation lines. Includes tabs. Save current parameter.
      case space || tab:
        {
          scanner.skipWhitespace(skipTabs: true); // preemptive
          flushBuffer();
        }

      default:
        {
          // Parameters only allow alpha-numeric characters. Cannot be null here
          if (!current!.isPrintable()) {
            throw const FormatException(
              'Only printable characters are allowed in a parameter',
            );
          }

          buffer.writeCharCode(current);
        }
    }

    scanner.skipCharAtCursor();
    current = scanner.charAtCursor;
  }

  flushBuffer(); // Just incase
  return _ReservedImpl(name: name, parameters: params);
}
