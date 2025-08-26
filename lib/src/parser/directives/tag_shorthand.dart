part of 'directives.dart';

/// A tag shorthand for a node that may (not) be resolved to a [GlobalTag]
@immutable
final class TagShorthand extends SpecificTag<String> {
  TagShorthand._(super.tagHandle, super.suffix) : super.fromString();

  /// Creates a local tag from a valid tag uri without the leading `!`.
  factory TagShorthand.fromTagUri(TagHandle tagHandle, String suffix) =>
      TagShorthand._(
        tagHandle,
        _ensureIsTagUri(suffix, allowRestrictedIndicators: false),
      );

  @override
  String get prefix => tagHandle.handle;

  @override
  String toString() => '$prefix$content';

  /// Indicates a tag with with a single `!` prefix and no [content].
  ///
  /// `!!` is invalid while `?` cannot be specified.
  bool get isNonSpecific =>
      tagHandle.handleVariant == TagHandleVariant.primary && content.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TagShorthand && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// Parses a [TagShorthand]
TagShorthand parseTagShorthand(GraphemeScanner scanner) {
  var handle = TagHandle.primary();
  scanner.skipCharAtCursor(); // Ignore leading "!"

  /// Quickly extract the remaining shorthand characters as valid uri chars
  /// that must be escaped since this is a secondary tag
  if (scanner.charAtCursor == tag) {
    handle = TagHandle.secondary();
    scanner.skipCharAtCursor();
    return TagShorthand._(
      handle,
      _parseTagUri(scanner, allowRestrictedIndicators: false),
    );
  }

  final buffer = StringBuffer();
  var hasNonAlphaNumChar = false;

  // Local tags require granular
  localTagChunker:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor!;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break localTagChunker;

      // We have to convert to named tag handle
      case tag:
        {
          // A named handle must have at least a character
          if (buffer.isEmpty) {
            throw const FormatException(
              'A named tag must not be empty. Expected at least a single '
              'alphanumeric character.',
            );
            // } else if (handle.handleVariant == TagHandleVariant.secondary) {
            //   throw FormatException(
            //     'A named tag must have a single "!" character. '
            //     'Any additional "!" must be escaped',
            //   );
          } else if (hasNonAlphaNumChar) {
            throw const FormatException(
              'A named tag can only have alphanumeric characters',
            );
          }

          /// The rest can be parsed as tag uri characters with strict
          /// escape requirements
          scanner.skipCharAtCursor();
          return TagShorthand._(
            TagHandle.named(buffer.toString()),
            _parseTagUri(scanner, allowRestrictedIndicators: false),
          );
        }

      /// If escaped, quickly parse remaining as tag uri of a shorthand with
      /// a primary tag handle. Cannot be named as named tag handles only
      /// accept alphanumeric chars
      ///   -> !tag%21
      case directive:
        {
          _parseTagUri(
            scanner,
            allowRestrictedIndicators: false,
            existingBuffer: buffer,
          );

          break localTagChunker;
        }

      // Normal alphanumeric
      case _ when char.isAlphaNumeric():
        buffer.writeCharCode(char);

      /// Any character that is not alphanumeric. This ensures we do not
      /// include non-alphanumeric uri char in a named handle.
      case _ when isUriChar(char):
        {
          buffer.writeCharCode(char);
          hasNonAlphaNumChar = true;
        }

      default:
        throw FormatException('"${char.asString()}" is not a valid URI char');
    }

    scanner.skipCharAtCursor();
  }

  // A local tag does not need to have a character i.e wildcard
  return TagShorthand._(handle, buffer.toString());
}
