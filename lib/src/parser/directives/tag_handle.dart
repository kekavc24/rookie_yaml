part of 'directives.dart';

/// Types of a [TagHandle]
enum TagHandleVariant {
  /// Normally used as a prefix for most [TagShorthand]s and all non-specific
  /// local tags
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

  /// [name] is a valid non-empty tag uri. Any `!`, `{`, `}`, `[`, or `]`
  /// must be encoded as 2 hex characters preceded by the `%`.
  factory TagHandle.named(String name) {
    assert(name.isNotEmpty, 'Name cannot be empty!');

    for (final (index, char) in Characters(name).indexed) {
      if (char.runes.firstOrNull.isNullOr((c) => !c.isAlphaNumeric())) {
        throw FormatException(
          'Found a non-alphanumeric char "$char" at index "$index"',
        );
      }
    }

    final prefix = tag.asString();
    return TagHandle._(TagHandleVariant.named, '$prefix$name$prefix');
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
TagHandle parseTagHandle(GraphemeScanner scanner) {
  // All tag handles must start with the indicator
  if (scanner.charAtCursor case var char when char != tag) {
    throw FormatException(
      'Expected a "${tag.asString()}" but found "${char.asString()}"',
    );
  }

  TagHandle tagHandle;

  switch (scanner.peekCharAfterCursor()) {
    // Just a single `!`
    case null || space || tab:
      tagHandle = TagHandle.primary();

    /// For secondary tags, parse as secondary. Let caller handle the "mess" or
    /// "success" that may follow.
    ///
    /// "Success" -> whitespace
    /// "Mess" -> throw if not whitespace
    case tag:
      scanner.skipCharAtCursor(); // Present in tag handle object
      tagHandle = TagHandle.secondary();

    // Strictly expect a named tag handle if not primary/secondary
    default:
      {
        final namedBuffer = StringBuffer();

        scanner
          ..takeUntil(
            includeCharAtCursor: true, // Prefer setting the leading "!"
            mapper: (c) => c.asString(),
            onMapped: (c) => namedBuffer.write(c),
            stopIf: (_, n) => !n.isAlphaNumeric(),
          )
          ..skipCharAtCursor();

        final current = scanner.charAtCursor;

        /// The named tag must not degenerate to a "!" or "!!". "!" is not
        /// alphanumeric
        if (current != tag || namedBuffer.length <= 1) {
          final str = current.asString();

          throw FormatException(
            'Invalid/incomplete named tag handle. Expected a tag with '
            'alphanumeric characters but found $namedBuffer'
            '${current == null ? str : '<$str>'}',
          );
        }

        namedBuffer.writeCharCode(tag); // Trailing "!"
        tagHandle = TagHandle._(TagHandleVariant.named, namedBuffer.toString());
      }
  }

  scanner.skipCharAtCursor();
  return tagHandle;
}
