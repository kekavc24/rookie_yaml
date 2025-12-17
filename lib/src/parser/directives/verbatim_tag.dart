part of 'directives.dart';

const _onNonEmptyVerbatimUri =
    'Verbatim tags are never resolved and should '
    'have a non-empty suffix';

/// Start of verbatim tag declaration
const verbatimStart = 0x3C;

/// End of verbatim tag declaration
const _verbatimEnd = folded;

/// Wraps a valid tag uri in verbatim
String _wrapAsVerbatim(String uri) =>
    '${tag.asString()}'
    '${verbatimStart.asString()}'
    '$uri'
    '${_verbatimEnd.asString()}';

/// Represents a tag explicitly declared in its raw form. Never resolved to
/// [GlobalTag]
///
/// {@category tag_types}
/// {@category declare_tags}
final class VerbatimTag extends ResolvedTag {
  VerbatimTag._(this.verbatim);

  /// Creates a verbatim tag from a valid tag uri. [uri] must start with the
  /// global tag uri scheme `tag:`. Any non-uri characters present will be
  /// normalized.
  factory VerbatimTag.fromTagUri(String uri) {
    if (!uri.startsWith('tag:')) {
      throw FormatException(
        'A verbatim tag uri must start with global tag prefix "tag:"',
        uri,
        0,
      );
    }

    return VerbatimTag._(
      _wrapAsVerbatim('!${normalizeTagUri(uri, includeRestricted: false)}'),
    );
  }

  /// Creates a verbatim tag from a local tag.
  factory VerbatimTag.fromTagShorthand(TagShorthand tag) {
    final uri = tag.toString().trim();

    if (tag.tagHandle.handleVariant != TagHandleVariant.primary) {
      throw FormatException(
        'Verbatim tags with a local tag must have a single "!" prefix',
      );
    } else if (uri.isEmpty) {
      throw FormatException(_onNonEmptyVerbatimUri);
    }

    return VerbatimTag._(_wrapAsVerbatim(uri));
  }

  @override
  TagHandle get tagHandle => TagHandle.primary();

  @override
  String get prefix => '';

  @override
  final String verbatim;

  @override
  String toString() => verbatim;

  @override
  bool operator ==(Object other) =>
      other is VerbatimTag && other.verbatim == verbatim;

  @override
  int get hashCode => verbatim.hashCode;
}

/// Parses a [VerbatimTag]
VerbatimTag parseVerbatimTag(SourceIterator iterator) {
  final startOffset = iterator.currentLineInfo.current;
  final buffer = StringBuffer();

  void isEndOrMatches({
    required bool Function(int char) matcher,
    required String errorOnMismatch,
  }) {
    if (iterator.isEOF || matcher(iterator.current)) {
      throwWithSingleOffset(
        iterator,
        message: errorOnMismatch,
        offset: iterator.currentLineInfo.current,
      );
    }

    buffer.writeCharCode(iterator.current);
    iterator.nextChar();
  }

  // Must start with a leading "!"
  isEndOrMatches(
    matcher: (char) => char != tag,
    errorOnMismatch: 'A verbatim tag must start with "!"',
  );

  // Must be followed by an opening bracket "<"
  isEndOrMatches(
    matcher: (char) => char != verbatimStart,
    errorOnMismatch:
        'Expected to find a "${verbatimStart.asString()}"'
        ' after "!"',
  );

  var isLocalTag = false;

  // This may be a local tag instead of a global one
  if (iterator.current == tag) {
    iterator.nextChar();
    buffer.writeCharCode(tag);
    isLocalTag = true;
  }

  // We can safely extract the remaining as uri characters
  final uri = _parseTagUri(
    iterator,
    allowRestrictedIndicators: true,
    isVerbatim: true,
  );

  if (uri.isEmpty) {
    throwWithApproximateRange(
      iterator,
      message: _onNonEmptyVerbatimUri,
      current: iterator.currentLineInfo.current,
      charCountBefore: buffer.length - 1,
    );
  } else if (!isLocalTag && !uri.startsWith('tag:')) {
    throwWithRangedOffset(
      iterator,
      message: 'Expected a tag uri starting the "tag:" uri scheme',
      start: startOffset,
      end: iterator.currentLineInfo.current,
    );
  }

  buffer.write(uri);

  isEndOrMatches(
    matcher: (char) => char != _verbatimEnd,
    errorOnMismatch:
        'Expected to find a "${_verbatimEnd.asString()}"'
        ' after parsing a verbatim tag',
  );

  return VerbatimTag._(buffer.toString());
}
