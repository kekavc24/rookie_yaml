part of 'directives.dart';

/// A tag shorthand for a node that may (not) be resolved to a [GlobalTag]
@immutable
final class LocalTag extends SpecificTag<String> {
  LocalTag._(super.tagHandle, super.suffix) : super.fromString();

  /// Creates a local tag from a valid tag uri without the leading `!`.
  factory LocalTag.fromTagUri(TagHandle tagHandle, String suffix) => LocalTag._(
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
      other is LocalTag && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// Parses a [LocalTag]
LocalTag parseLocalTag(ChunkScanner scanner) {
  var handle = TagHandle.primary();
  scanner.skipCharAtCursor(); // Ignore leading "!"

  /// Quickly extract the remaining shorthand characters as valid uri chars
  /// that must be escaped since this is a secondary tag
  if (scanner.charAtCursor == _tagIndicator) {
    handle = TagHandle.secondary();
    scanner.skipCharAtCursor();
    return LocalTag._(
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
    final ReadableChar(:string) = char;

    switch (char) {
      case LineBreak _ || WhiteSpace _:
        break localTagChunker;

      // We have to convert to named tag handle
      case _tagIndicator:
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
          return LocalTag._(
            TagHandle.named(buffer.toString()),
            _parseTagUri(scanner, allowRestrictedIndicators: false),
          );
        }

      /// If escaped, quickly parse remaining as tag uri of a shorthand with
      /// a primary tag handle. Cannot be named as named tag handles only
      /// accept alphanumeric chars
      ///   -> !tag%21
      case Indicator.directive:
        {
          _parseTagUri(
            scanner,
            allowRestrictedIndicators: false,
            existingBuffer: buffer,
          );

          break localTagChunker;
        }

      // Normal alphanumeric
      case _ when isAlphaNumeric(char):
        buffer.write(string);

      /// Any character that is not alphanumeric. This ensures we do not
      /// include non-alphanumeric uri char in a named handle.
      case _ when isUriChar(char):
        {
          buffer.write(string);
          hasNonAlphaNumChar = true;
        }

      default:
        throw FormatException('"$string" is not a valid URI char');
    }

    scanner.skipCharAtCursor();
  }

  // A local tag does not need to have a character i.e wildcard
  return LocalTag._(handle, buffer.toString());
}
