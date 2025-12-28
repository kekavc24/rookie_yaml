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

Never _charNotAllowedException(SourceIterator iterator) =>
    throwWithSingleOffset(
      iterator,
      message: 'The current character is not allowed in block scalar header',
      offset: iterator.currentLineInfo.current,
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
  required CharWriter buffer,
  required bool wroteToBuffer,
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
    if (!wroteToBuffer) return;
    countToWrite = 1; // Trailing line breaks after final one are ignored
  }

  /// Keep all trailing empty lines after for `keep` indicator
  bufferHelper(lineBreaks.take(countToWrite), buffer);
}

/// Skips the carriage return `\r` in a `\r\n` combination and returns the
/// line feed `\n`.
int skipCrIfPossible(int lineBreak, {required SourceIterator iterator}) {
  var maybeCR = lineBreak;

  if (maybeCR == carriageReturn && iterator.peekNextChar() == lineFeed) {
    maybeCR = lineFeed;
    iterator.nextChar();
  }

  return maybeCR;
}

/// Folds line breaks only if [isLiteral] and [lastNonEmptyWasIndented] are `
/// false`. Line breaks between indented lines are never folded.
void _maybeFoldLF(
  CharWriter buffer, {
  required bool isLiteral,
  required bool wroteToBuffer,
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
        ? [if (wroteToBuffer) space]
        : lineBreaks.skip(1);
  }

  bufferHelper(toWrite, buffer);
  lineBreaks.clear();
}

/// Infers the indent of the block scalar being parsed. `inferredIndent` may
/// be null if the line was empty, that is, no characters or all characters
/// are just white space characters.
({int inferredIndent, bool isEmptyLine, bool startsWithTab}) _inferIndent(
  SourceIterator iterator, {
  required CharWriter buffer,
  required int scannedIndent,
  required void Function() callBeforeTabWrite,
}) {
  var startsWithTab = false;
  final canBeIndent = scannedIndent + skipWhitespace(iterator).length;

  final charAfter = iterator.peekNextChar();

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
    takeFromIteratorUntil(
      iterator,
      includeCharAtCursor: false,
      mapper: (rc) => rc,
      onMapped: buffer,
      stopIf: (_, possibleNext) => !possibleNext.isWhiteSpace(),
    );

    // This line cannot be used to determine the
    if (iterator.peekNextChar().isNotNullAnd((c) => c.isLineBreak())) {
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
