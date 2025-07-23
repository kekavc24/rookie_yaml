part of 'directives.dart';

const _onNonEmptyVerbatimUri =
    'Verbatim tags are never resolved and should '
    'have a non-empty suffix';

/// Start of verbatim tag declaration
final verbatimStart = ReadableChar.scanned('<');

/// End of verbatim tag declaration
const _verbatimEnd = Indicator.folded;

/// Wraps a valid tag uri in verbatim
String _wrapAsVerbatim(String uri) =>
    '${_tagIndicator.string}$verbatimStart$uri${_verbatimEnd.string}';

/// Represents a tag explicitly declared in its raw form. Never resolved to
/// [GlobalTag]
@immutable
final class VerbatimTag implements ResolvedTag {
  const VerbatimTag._(this.verbatim);

  /// Creates a verbatim tag from a valid tag uri
  factory VerbatimTag.fromTagUri(String uri) {
    return VerbatimTag._(
      _wrapAsVerbatim(_ensureIsTagUri(uri, allowRestrictedIndicators: false)),
    );
  }

  /// Creates a verbatim tag from a local tag
  factory VerbatimTag.fromLocalTag(LocalTag tag) {
    final uri = tag.toString().trim();

    if (tag.tagHandle.handleVariant != TagHandleVariant.primary) {
      throw const FormatException(
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

  final ReadableChar(string: vStart, unicode: vsCode) = verbatimStart;

  // Must be followed by an opening bracket "<"
  isNotNullOrMatches(
    matcher: (char) => char.unicode == vsCode,
    errorOnMismatch: 'Expected to find a "$vStart" after "!"',
  );
  skipAndMove();

  // This may be a local tag instead of a global one
  if (charAtCursor == _tagIndicator) {
    skipAndMove();
    buffer.write(_tagIndicator.string);
  }

  // We can safely extract the remaining as uri characters
  final uri = _parseTagUri(
    scanner,
    allowRestrictedIndicators: true,
    isVerbatim: true,
  );

  if (uri.isEmpty) {
    throw const FormatException(_onNonEmptyVerbatimUri);
  }

  charAtCursor = scanner.charAtCursor;
  buffer.write(uri);

  final ReadableChar(string: vEnd, unicode: veCode) = _verbatimEnd;

  isNotNullOrMatches(
    matcher: (char) => char == _verbatimEnd,
    errorOnMismatch: 'Expected to find a "$vEnd" after parsing a verbatim tag',
  );
  skipAndMove();

  return VerbatimTag._(buffer.toString());
}
