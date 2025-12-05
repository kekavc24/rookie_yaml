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

  /// Creates a verbatim tag from a valid tag uri. [uri] should not have a
  /// leading `!`.
  factory VerbatimTag.fromTagUri(String uri) => VerbatimTag._(
    _wrapAsVerbatim(
      '!'
      '${_ensureIsTagUri(uri, allowRestrictedIndicators: false)}',
    ),
  );

  /// Creates a verbatim tag from a local tag
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
VerbatimTag parseVerbatimTag(GraphemeScanner scanner) {
  final startOffset = scanner.lineInfo().current;
  var charAtCursor = scanner.charAtCursor;

  void skipAndMove() {
    scanner.skipCharAtCursor();
    charAtCursor = scanner.charAtCursor;
  }

  final buffer = StringBuffer();

  void isNotNullNorMatches({
    required bool Function(int char) matcher,
    required String errorOnMismatch,
  }) {
    if (charAtCursor.isNullOr(matcher)) {
      throwWithSingleOffset(
        scanner,
        message: errorOnMismatch,
        offset: scanner.lineInfo().current,
      );
    }

    buffer.writeCharCode(charAtCursor!);
  }

  // Must start with a leading "!"
  isNotNullNorMatches(
    matcher: (char) => char != tag,
    errorOnMismatch: 'A verbatim tag must start with "!"',
  );
  skipAndMove();

  // Must be followed by an opening bracket "<"
  isNotNullNorMatches(
    matcher: (char) => char != verbatimStart,
    errorOnMismatch:
        'Expected to find a "${verbatimStart.asString()}"'
        ' after "!"',
  );
  skipAndMove();

  var isLocalTag = false;

  // This may be a local tag instead of a global one
  if (charAtCursor == tag) {
    skipAndMove();
    buffer.writeCharCode(tag);
    isLocalTag = true;
  }

  // We can safely extract the remaining as uri characters
  final uri = _parseTagUri(
    scanner,
    allowRestrictedIndicators: true,
    isVerbatim: true,
  );

  if (uri.isEmpty) {
    throwWithApproximateRange(
      scanner,
      message: _onNonEmptyVerbatimUri,
      current: scanner.lineInfo().current,
      charCountBefore: buffer.length - 1,
    );
  } else if (!isLocalTag && !uri.startsWith('tag:')) {
    throwWithRangedOffset(
      scanner,
      message: 'Expected a tag uri starting the "tag:" uri scheme',
      start: startOffset,
      end: scanner.lineInfo().current,
    );
  }

  charAtCursor = scanner.charAtCursor;
  buffer.write(uri);

  isNotNullNorMatches(
    matcher: (char) => char != _verbatimEnd,
    errorOnMismatch:
        'Expected to find a "${_verbatimEnd.asString()}"'
        ' after parsing a verbatim tag',
  );
  skipAndMove();

  return VerbatimTag._(buffer.toString());
}
