part of 'directives.dart';

/// A tag shorthand for a node that may (not) be resolved to a [GlobalTag]
///
/// {@category tag_types}
/// {@category declare_tags}
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
TagShorthand parseTagShorthand(SourceIterator iterator) {
  if (iterator.current != tag) {
    throwWithSingleOffset(
      iterator,
      message: 'Expected a tag indicator "!"',
      offset: iterator.currentLineInfo.current,
    );
  }

  /// Local tags can be fast forwarded quite easily based on some granular
  /// quirky checks. Ergo, the non-dependence on [parseTagHandle] is
  /// intentional. Any refactors should take that into account.

  // *Just a gap*
  iterator.nextChar(); // Ignore leading "!"

  /// Quickly extract the remaining shorthand characters as valid uri chars
  /// that must be escaped since this is a secondary tag shorthand
  if (iterator.current == tag) {
    iterator.nextChar();
    return TagShorthand._(
      TagHandle.secondary(),
      _parseTagUri(iterator, allowRestrictedIndicators: false),
    );
  }

  final buffer = StringBuffer();
  var hasNonAlphaNumChar = false;

  localTagChunker:
  while (!iterator.isEOF) {
    final char = iterator.current;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break localTagChunker;

      // We have to convert to named tag handle
      case tag:
        {
          /// This condition is just a safety net. Never happens. Consecutive
          /// tag indicators forces the shorthand to be treated as a secondary
          /// tag shorthand. This happens before this loop starts. You can never
          /// be too sure though :)
          if (buffer.isEmpty) {
            throwWithSingleOffset(
              iterator,
              message:
                  'A named tag must not be empty. Expected at least a single '
                  'alphanumeric character.',
              offset: iterator.currentLineInfo.current,
            );
          } else if (hasNonAlphaNumChar) {
            throwWithApproximateRange(
              iterator,
              message: 'A named tag can only have alphanumeric characters',
              current: iterator.currentLineInfo.current,

              /// Highlight the buffered shorthand including the "!" we skipped
              /// at the beginning.
              charCountBefore: buffer.length + 1,
            );
          }

          /// The rest can be parsed as tag uri characters with strict
          /// escape requirements
          iterator.nextChar();
          return TagShorthand._(
            TagHandle.named(buffer.toString()),
            _parseTagUri(iterator, allowRestrictedIndicators: false),
          );
        }

      /// If escaped, quickly parse remaining as tag uri of a shorthand with
      /// a primary tag handle. Cannot be named as named tag handles only
      /// accept alphanumeric chars
      ///   -> !tag%21
      case directive:
        {
          _parseTagUri(
            iterator,
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
        throwWithSingleOffset(
          iterator,
          message: 'The current character is not a valid URI char',
          offset: iterator.currentLineInfo.current,
        );
    }

    iterator.nextChar();
  }

  // A local tag does not need to have a character i.e wildcard
  return TagShorthand._(TagHandle.primary(), buffer.toString());
}
