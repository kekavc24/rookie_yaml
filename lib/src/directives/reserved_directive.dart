part of 'directives.dart';

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
  String toString() => _dumpDirective(this);
}

final class _ReservedImpl extends ReservedDirective {
  _ReservedImpl({required super.name, required super.parameters});
}

/// Parses a [ReservedDirective]
ReservedDirective _parseReservedDirective(
  String name, {
  required ChunkScanner scanner,
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

  while (scanner.canChunkMore && current is! LineBreak?) {
    // Intentional switch case use!
    switch (current) {
      /// Skip separation lines. Includes tabs. Save current parameter.
      case WhiteSpace _:
        {
          scanner.skipWhitespace(skipTabs: true); // preemptive
          flushBuffer();
        }

      default:
        {
          // Parameters only allow alpha-numeric characters. Cannot be null here
          if (!isPrintable(current)) {
            throw const FormatException(
              'Only printable characters are allowed in a parameter',
            );
          }

          buffer.write(current.string);
        }
    }

    scanner.skipCharAtCursor();
    current = scanner.charAtCursor;
  }

  flushBuffer(); // Just incase
  return _ReservedImpl(name: name, parameters: params);
}
