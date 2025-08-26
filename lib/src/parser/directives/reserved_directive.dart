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

  /// Reserved directives are prone to endless grouped token consumption between
  /// with whitespace . YAML allows comments in directives (tricky).
  /// The condition below may seem unorthodox. It's simple.
  /// Exit if:
  ///   1. If we have no more tokens and the char at cursor is not null
  ///   2. If (1) stands, capture the non-null [current] and check if we reached
  ///      the end of the line.
  ///   3. If (2) stands, check if the captured non-null [current] is a comment
  ///      only if the char before was non-null and a separation space
  ///      (tab/space).
  while (scanner.canChunkMore &&
      current.isNotNullAnd(
        (cursor) =>
            !cursor.isLineBreak() &&
            !(cursor == comment &&
                scanner.charBeforeCursor.isNotNullAnd((c) => c.isWhiteSpace())),
      )) {
    // Intentional switch case use!
    switch (current) {
      // Skip separation lines. Includes tabs. Save current parameter.
      case space || tab:
        {
          scanner.skipWhitespace(skipTabs: true);
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
