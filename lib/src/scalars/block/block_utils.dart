part of 'block_scalar.dart';

/// A block scalar's header information.
///
///   * `isLiteral` - indicates if `literal` or `folded`.
///   * `chomping` - indicates how trailing lines are handled.
///   * `indentIndicator` - additional indent to include to the node's indent
typedef _BlockHeaderInfo =
    ({bool isLiteral, ChompingIndicator chomping, int? indentIndicator});

/// Block scalar's indicators that convey how the scalar should be `chomped`
/// or additional indent to apply
typedef _IndicatorInfo = (ChompingIndicator chomping, int? indentIndicator);

/// Checks the block's scalar style.
bool? _isLiteralIndicator(ReadableChar? char) {
  return switch (char) {
    Indicator.folded => false,
    Indicator.literal => true,
    _ => null,
  };
}

/// Checks the block scalar's chomping indicator. Intentionally returns `null`
/// if the [ReadableChar] is not a [ChompingIndicator].
ChompingIndicator? _resolveChompingIndicator(ReadableChar char) {
  return switch (char.string) {
    '+' => ChompingIndicator.keep,
    '-' => ChompingIndicator.strip,
    _ => null,
  };
}

FormatException _charNotAllowedException(String char) =>
    FormatException('"$char" character is not allowed in block scalar header');

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
  required StringBuffer contentBuffer,
  required List<LineBreak> lineBreaks,
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
  contentBuffer.writeAll(lineBreaks.take(countToWrite).map((rc) => rc.string));
}

/// Skips the carriage return `\r` in a `\r\n` combination and returns the
/// line feed `\n`.
LineBreak skipCrIfPossible(LineBreak char, {required ChunkScanner scanner}) {
  var maybeCR = char;

  if (maybeCR == LineBreak.carriageReturn &&
      scanner.peekCharAfterCursor() == LineBreak.lineFeed) {
    maybeCR = LineBreak.lineFeed;
    scanner.skipCharAtCursor();
  }

  return maybeCR;
}

/// Folds line breaks only if [isLiteral] and [lastNonEmptyWasIndented] are `
/// false`. Line breaks between indented lines are never folded.
void _foldLfIfPossible(
  StringBuffer contentBuffer, {
  required bool isLiteral,
  required bool lastNonEmptyWasIndented,
  required List<LineBreak> lineBreaks,
}) {
  if (lineBreaks.isEmpty) return;

  Iterable<ReadableChar> toWrite = lineBreaks;

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
    toWrite =
        lineBreaks.length == 1
            ? [if (contentBuffer.isNotEmpty) WhiteSpace.space]
            : lineBreaks.skip(1);
  }

  contentBuffer.writeAll(toWrite.map((rc) => rc.string));
  lineBreaks.clear();
}

/// Infers the indent of the block scalar being parsed. `inferredIndent` may
/// be null if the line was empty, that is, no characters or all characters
/// are just white space characters.
({int? inferredIndent, bool startsWithTab}) _determineIndent(
  ChunkScanner scanner, {
  required StringBuffer contentBuffer,
  required int scannedIndent,
  required void Function() callBeforeTabWrite,
}) {
  var startsWithTab = false;
  final canBeIndent = scannedIndent + scanner.skipWhitespace().length;

  final charAfter = scanner.peekCharAfterCursor();

  /// We have to be sure that is not empty.
  ///
  /// See: https://yaml.org/spec/1.2.2/#empty-lines
  if (charAfter is LineBreak) {
    return (inferredIndent: null, startsWithTab: false);
  }

  /// It's still empty if just tabs which qualifies them as separation in a
  /// line.
  ///
  /// See: https://yaml.org/spec/1.2.2/#62-separation-spaces
  if (charAfter == WhiteSpace.tab) {
    callBeforeTabWrite();
    contentBuffer.writeAll(
      scanner.takeUntil(
        includeCharAtCursor: false,
        mapper: (rc) => rc.string,
        stopIf: (_, possibleNext) => possibleNext is! WhiteSpace,
      ),
    );

    // This line cannot be used to determine the
    if (scanner.peekCharAfterCursor() is LineBreak) {
      return (inferredIndent: null, startsWithTab: true);
    }

    startsWithTab = true;
  }

  return (inferredIndent: canBeIndent, startsWithTab: startsWithTab);
}

const _takeOrSkip = 1;
const _whitespace = WhiteSpace.space;

/// Preserves line breaks in two ways in `folded` scalar style (line breaks in
/// `literal` style are always preserved):
///
/// 1. If the current line is indented, all buffered lines are never folded.
/// 2. If the current line is indented but was preceded by a single/several
/// empty line(s) before the last non-empty indented line, a space character is
/// added to indicate that despite this line being empty it signifies content
/// and was never `folded`.
Iterable<ReadableChar> _preserveEmptyIndented({
  required bool isLiteral,
  required bool lastWasIndented,
  required List<LineBreak> lineBreaks,
}) {
  ///
  /// All buffered line breaks are written by default in both `literal`.
  ///
  /// When `folded`, we need to ensure empty lines between two indented lines
  /// can be reproduced if the string was to be "un-folded". Emit a white space
  /// before each line break after the first one.
  ///
  /// See: https://yaml.org/spec/1.2.2/#813-folded-style:~:text=Lines%20starting%20with%20white%20space%20characters%20(more%2Dindented%20lines)%20are%20not%20folded.
  return isLiteral || !lastWasIndented
      ? lineBreaks
      : lineBreaks
          .take(_takeOrSkip)
          .cast<ReadableChar>()
          .followedBy(
            lineBreaks.skip(_takeOrSkip).expand((value) sync* {
              yield _whitespace;
              yield value;
            }),
          );
}
