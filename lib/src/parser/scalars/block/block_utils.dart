part of 'block_scalar.dart';

/// A block scalar's header information.
///
///   * `isLiteral` - indicates if `literal` or `folded`.
///   * `chomping` - indicates how trailing lines are handled.
///   * `indentIndicator` - additional indent to include to the node's indent
typedef _BlockHeaderInfo = ({
  bool isLiteral,
  ChompingIndicator chomping,
  int? indentIndicator,
});

/// Block scalar's indicators that convey how the scalar should be `chomped`
/// or additional indent to apply
typedef _IndicatorInfo = (ChompingIndicator chomping, int? indentIndicator);

/// Checks the block's scalar style.
bool? _isLiteralIndicator(int? char) {
  return switch (char) {
    folded => false,
    literal => true,
    _ => null,
  };
}

/// Checks the block scalar's chomping indicator. Intentionally returns `null`
/// if the [ReadableChar] is not a [ChompingIndicator].
ChompingIndicator? _resolveChompingIndicator(int char) {
  return switch (char) {
    0x2B => ChompingIndicator.keep,
    0x2D => ChompingIndicator.strip,
    _ => null,
  };
}

Never _charNotAllowedException(GraphemeScanner scanner) =>
    throwWithSingleOffset(
      scanner,
      message: 'The current character is not allowed in block scalar header',
      offset: scanner.lineInfo().current,
    );

/// Chomps the trailing line breaks of a parsed block scalar.
///
/// [ChompingIndicator.strip] - trims all trailing line breaks.
///
/// [ChompingIndicator.clip] - excludes the final line break and trims all the
/// trailing line breaks after it. It degenerates to [ChompingIndicator.strip]
/// if the scalar is empty or contains only line breaks.
///
/// [ChompingIndicator.keep] - no trailing line break is trimmed.
void _chompLineBreaks(
  ChompingIndicator indicator, {
  required ScalarBuffer contentBuffer,
  required List<int> lineBreaks,
}) {
  // Exclude line breaks from content by default
  if (lineBreaks.isEmpty || indicator == ChompingIndicator.strip) return;

  /// For `clip` and `keep`, the final line break is content.
  ///
  /// See https://yaml.org/spec/1.2.2/#8112-block-chomping-indicator
  ///
  var countToWrite = lineBreaks.length;

  if (indicator == ChompingIndicator.clip) {
    /// We clip all line breaks if the scalar is empty.
    ///
    /// See: "https://yaml.org/spec/1.2.2/#812-literal-style:~:text=If
    /// %20a%20block%20scalar%20consists%20only%20of%20empty%20lines%2C%20
    /// then%20these%20lines%20are%20considered%20as%20trailing%20lines%20and
    /// %20hence%20are%20affected%20by%20chomping"
    if (contentBuffer.isEmpty) return;
    countToWrite = 1; // Trailing line breaks after final one are ignored
  }

  /// Keep all trailing empty lines after for `keep` indicator
  contentBuffer.writeAll(lineBreaks.take(countToWrite));
}

/// Skips the carriage return `\r` in a `\r\n` combination and returns the
/// line feed `\n`.
int skipCrIfPossible(int lineBreak, {required GraphemeScanner scanner}) {
  var maybeCR = lineBreak;

  if (maybeCR == carriageReturn && scanner.charAfter == lineFeed) {
    maybeCR = lineFeed;
    scanner.skipCharAtCursor();
  }

  return maybeCR;
}

/// Folds line breaks only if [isLiteral] and [lastNonEmptyWasIndented] are `
/// false`. Line breaks between indented lines are never folded.
void _maybeFoldLF(
  ScalarBuffer contentBuffer, {
  required bool isLiteral,
  required bool lastNonEmptyWasIndented,
  required List<int> lineBreaks,
}) {
  if (lineBreaks.isEmpty) return;

  Iterable<int> toWrite = lineBreaks;

  // Fold only if not literal and last non-empty line was not indented.
  if (!isLiteral && !lastNonEmptyWasIndented) {
    /// `YAML` requires we emit a space if it's a single line break as it
    /// indicates we are joining 2 previously broken lines.
    ///
    /// The first `\n` is included as part of the folding in `folded` block
    /// style. We intentionally exclude it if the first line is not empty since
    /// it serves no purpose but a transition from the block scalar header.
    ///
    /// However, if followed by a `\n`, `YAML` implies it should be folded from
    /// the docs.
    toWrite = lineBreaks.length == 1
        ? [if (contentBuffer.isNotEmpty) space]
        : lineBreaks.skip(1);
  }

  contentBuffer.writeAll(toWrite);
  lineBreaks.clear();
}

/// Infers the indent of the block scalar being parsed. `inferredIndent` may
/// be null if the line was empty, that is, no characters or all characters
/// are just white space characters.
({int inferredIndent, bool isEmptyLine, bool startsWithTab}) _inferIndent(
  GraphemeScanner scanner, {
  required ScalarBuffer contentBuffer,
  required int scannedIndent,
  required void Function() callBeforeTabWrite,
}) {
  var startsWithTab = false;
  final canBeIndent = scannedIndent + scanner.skipWhitespace().length;

  final charAfter = scanner.charAfter;

  /// We have to be sure that is not empty.
  ///
  /// See: https://yaml.org/spec/1.2.2/#empty-lines
  if (charAfter.isNotNullAnd((c) => c.isLineBreak())) {
    return (
      inferredIndent: canBeIndent,
      isEmptyLine: true,
      startsWithTab: false,
    );
  }

  /// It's still empty if just tabs which qualifies them as separation in a
  /// line.
  ///
  /// See: https://yaml.org/spec/1.2.2/#62-separation-spaces
  if (charAfter == tab) {
    callBeforeTabWrite();
    scanner.takeUntil(
      includeCharAtCursor: false,
      mapper: (rc) => rc,
      onMapped: contentBuffer.writeChar,
      stopIf: (_, possibleNext) => !possibleNext.isWhiteSpace(),
    );

    // This line cannot be used to determine the
    if (scanner.charAfter.isNotNullAnd((c) => c.isLineBreak())) {
      return (
        inferredIndent: canBeIndent,
        isEmptyLine: true,
        startsWithTab: true,
      );
    }

    startsWithTab = true;
  }

  return (
    inferredIndent: canBeIndent,
    isEmptyLine: false,
    startsWithTab: startsWithTab,
  );
}

/// Single char for document end marker, `...`
const docEndSingle = period;

/// Single char for directives end marker, `---`
const directiveEndSingle = blockSequenceEntry;

/// Checks and returns if the next sequence of characters are valid
/// [DocumentMarker]. Defaults to [DocumentMarker.none] if not true.
/// May throw if non-whitespace characters are declared in the same line as
/// document end markers (`...`).
///
/// `NOTE:` This function is currently restricted to `block` or `block-like`
/// styles such `plain` scalars. While `YAML` has a test which indicates that
/// the markers should not be in other scalar styles, it beats the purpose
/// of having the markers in the first place.
///
/// ```yaml
/// # Here is fine. Plain and block styles have no markers.
/// ---scalar
/// ---
///
/// # Why here? If double-quoted and single-quoted styles have their own
/// # markers which tell us when to stop parsing them?
/// #
/// # Parsing should continue unless
/// --- "
/// my multi-line scalar with markers
///
/// ...
/// ---
/// "
/// ```
DocumentMarker checkForDocumentMarkers(
  GraphemeScanner scanner, {
  required void Function(List<int> buffered) onMissing,
}) {
  var charAtCursor = scanner.charAtCursor;
  final markers = <int>[];

  void pointToNext() {
    scanner.skipCharAtCursor();
    charAtCursor = scanner.charAtCursor;
  }

  /// Document markers, that `...` and `---` have no indent. They must be
  /// top level. Check before falling back to checking if it is a top level
  /// scalar.
  ///
  /// We insist on it being top level because the markers have no indent
  /// before. They have a -1 indent at this point or zero depending on how
  /// far along the parsing this is called.
  if (charAtCursor case docEndSingle || directiveEndSingle) {
    const expectedCount = 3;
    final match = charAtCursor;

    final skipped = scanner.takeUntil(
      includeCharAtCursor: true,
      mapper: (v) => v,
      onMapped: (v) => markers.add(v),
      stopIf: (count, possibleNext) {
        return count == expectedCount || possibleNext != match;
      },
    );

    pointToNext();

    if (skipped == expectedCount) {
      /// YAML insists document markers should not have any characters
      /// after unless its just whitespace or comments.
      if (match == docEndSingle) {
        if (charAtCursor.isNotNullAnd((c) => c.isWhiteSpace())) {
          scanner.skipWhitespace(skipTabs: true);
          pointToNext();
        }

        if (charAtCursor.isNullOr((c) => c.isLineBreak() || c == comment)) {
          return DocumentMarker.documentEnd;
        }

        final (:start, :current) = scanner.lineInfo();

        throwWithRangedOffset(
          scanner,
          message:
              'Document end markers "..." can only have whitespace/comments'
              ' after',
          start: start,
          end: current,
        );
      }

      // Directives end markers can have either
      if (charAtCursor.isNullOr((c) => c.isLineBreak() || c.isWhiteSpace())) {
        return DocumentMarker.directiveEnd;
      }
    }
  }

  onMissing(markers);
  return DocumentMarker.none;
}
