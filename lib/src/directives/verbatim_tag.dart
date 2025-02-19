part of 'directives.dart';

const _onNonEmptyVerbationUri =
    'Verbatim tags are never resolved and should '
    'have a non-empty suffix';

final _verbatimStart = GraphemeChar.wrap('<');
final _verbatimEnd = GraphemeChar.wrap('>');

String _wrapAsVerbatim(String uri) =>
    '${_tagIndicator.string}$_verbatimStart$uri$_verbatimEnd';

final class VerbatimTag implements _ResolvedTag {
  VerbatimTag._(this.verbatim);

  factory VerbatimTag.fromTagUri(String uri) {
    return VerbatimTag._(
      _ensureIsTagUri(uri, allowRestrictedIndicators: false),
    );
  }

  factory VerbatimTag.fromLocalTag(LocalTag tag) {
    final uri = tag.toString().trim();

    if (tag.tagHandle.handleVariant != TagHandleVariant.primary) {
      throw FormatException(
        'Verbatim tags with a local tag must have a single "!" prefix',
      );
    } else if (uri.isEmpty) {
      throw FormatException(_onNonEmptyVerbationUri);
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

VerbatimTag parseVerbatimTag(ChunkScanner scanner) {
  var charAtCursor = scanner.charAtCursor;

  void skipAndMove() {
    scanner.skipCharAtCursor();
    charAtCursor = scanner.charAtCursor;
  }

  final buffer = StringBuffer();

  void isNotNullOrMatches({
    required bool Function(ReadableChar char) matcher,
    required String errorOnMismatch,
  }) {
    if (charAtCursor == null || !matcher(charAtCursor!)) {
      throw FormatException(errorOnMismatch);
    }

    buffer.write(charAtCursor!.string);
  }

  // Must start with a leading "!"
  isNotNullOrMatches(
    matcher: (char) => char == _tagIndicator,
    errorOnMismatch: 'A verbatim tag must start with "!"',
  );
  skipAndMove();

  final GraphemeChar(string: vStart, unicode: vsCode) = _verbatimStart;

  // Must be followed by an opening bracket "<"
  isNotNullOrMatches(
    matcher: (char) => char.unicode == vsCode,
    errorOnMismatch: 'Expected to find a "$vStart" after "!"',
  );
  skipAndMove();

  // This may be a local tag instead of a global one
  if (charAtCursor == _tagIndicator) {
    skipAndMove();
  }

  // We can safely extract the remaining as uri characters
  final uri = _parseTagUri(
    scanner,
    allowRestrictedIndicators: true,
    isVerbatim: true,
  );

  if (uri.isEmpty) {
    throw FormatException(_onNonEmptyVerbationUri);
  }

  charAtCursor = scanner.charAtCursor;
  buffer.write(uri);

  final GraphemeChar(string: vEnd, unicode: veCode) = _verbatimEnd;

  isNotNullOrMatches(
    matcher: (char) => char.unicode == veCode,
    errorOnMismatch: 'Expected to find a "$vEnd" after "!"',
  );
  skipAndMove();

  return VerbatimTag._(buffer.toString());
}
