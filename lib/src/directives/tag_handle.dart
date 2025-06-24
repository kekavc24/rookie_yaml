part of 'directives.dart';

const _tagIndicator = Indicator.tag;

/// Types of a [TagHandle]
enum TagHandleVariant {
  /// Normally used as a prefix for most [LocalTag]s
  primary('!'),

  /// Prefix for tags that resolve to `tag:yaml.org,2002:` unless overriden
  /// by the `%TAG` directive globally.
  secondary('!!'),

  /// Prefix which supports a custom name. Must provide trailing `!` to
  /// indicate the end of the name.
  named('');

  const TagHandleVariant(this._handle);

  final String _handle;
}

/// Represents a prefix for any [Tag] declared in `YAML`
@immutable
final class TagHandle {
  TagHandle._(this.handleVariant, String? handle)
    : handle = handle ?? handleVariant._handle;

  /// `!`
  TagHandle.primary() : this._(TagHandleVariant.primary, null);

  /// `!!`
  TagHandle.secondary() : this._(TagHandleVariant.secondary, null);

  /// [name] is a valid non-empty tag uri surrounded by a single `!`. Any other
  /// `!` must be encoded as 2 hex characters preceded by the `%`.
  factory TagHandle.named(String name) {
    assert(name.isNotEmpty, 'Name cannot be empty!');

    var modded = name;

    for (final (index, char) in name.split('').indexed) {
      if (!isAlphaNumeric(GraphemeChar.wrap(char))) {
        throw FormatException(
          'Found a non-alphanumeric char "$char" at index "$index"',
        );
      }
    }

    final pattern = _tagIndicator.string;

    if (!name.startsWith(pattern)) modded = '$pattern$modded';
    if (!name.endsWith(pattern)) modded = '$modded$pattern';
    return TagHandle._(TagHandleVariant.named, modded);
  }

  /// Type of tag handle
  final TagHandleVariant handleVariant;

  /// Prefix denoting the tag handle
  final String handle;

  @override
  String toString() => handle;

  @override
  bool operator ==(Object other) =>
      other is TagHandle &&
      other.handleVariant == handleVariant &&
      other.handle == handle;

  @override
  int get hashCode => Object.hashAll([handleVariant, handle]);
}

/// Parses a [TagHandle]
TagHandle parseTagHandle(ChunkScanner scanner) {
  final char = scanner.charAtCursor;

  final indicatorStr = _tagIndicator.string;

  // All tag handles must start with the indicator
  if (char == null || char != _tagIndicator) {
    throw FormatException(
      'Expected a $indicatorStr but found '
      '${char?.string ?? 'nothing'}',
    );
  }

  TagHandle tagHandle;

  switch (scanner.peekCharAfterCursor()) {
    // Just a single `!`
    case WhiteSpace _:
      tagHandle = TagHandle.primary();

    /// For secondary tags, parse as secondary. Let caller handle the "mess" or
    /// "success" that may follow.
    ///
    /// "Success" -> whitespace
    /// "Mess" -> throw if not whitespace
    case _tagIndicator:
      scanner.skipCharAtCursor(); // Present in tag handle object
      tagHandle = TagHandle.secondary();

    // Strictly expect a named tag handle if not primary/secondary
    default:
      {
        // Prefer setting the leading and trailing "!"
        final namedBuffer = StringBuffer(indicatorStr);

        final ChunkInfo(:charOnExit) = scanner.bufferChunk(
          (c) => namedBuffer.write(c.string),
          exitIf: (_, curr) => !isAlphaNumeric(curr),
        );

        if (charOnExit != _tagIndicator) {
          final bufferVal = namedBuffer.toString();

          throw FormatException(
            'Invalid named tag handle format. '
            'Expected !$bufferVal! but found $bufferVal<${charOnExit?.string}>',
          );
        }

        namedBuffer.write(indicatorStr); // Trailing "!"
        tagHandle = TagHandle.named(namedBuffer.toString());
      }
  }

  scanner.skipCharAtCursor();
  return tagHandle;
}
