part of 'block_scalar.dart';

typedef _BlockHeaderInfo = ({
  bool isLiteral,
  ChompingIndicator chomping,
  int? indentIndicator,
});

typedef _IndicatorInfo = (ChompingIndicator chomping, int? indentIndicator);

bool? _isLiteralIndicator(ReadableChar? char) {
  return switch (char) {
    Indicator.folded => false,
    Indicator.literal => true,
    _ => null
  };
}

ChompingIndicator? _resolveChompingIndicator(ReadableChar char) {
  return switch (char.string) {
    '+' => ChompingIndicator.keep,
    '-' => ChompingIndicator.strip,
    _ => null,
  };
}

FormatException _charNotAllowedException(String char) => FormatException(
      '"$char" character is not allowed in block scalar header',
    );

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

LineBreak skipCrIfPossible(LineBreak char, {required ChunkScanner scanner}) {
  var maybeCR = char;

  if (maybeCR == LineBreak.carriageReturn &&
      scanner.peekCharAfterCursor() == LineBreak.lineFeed) {
    maybeCR = LineBreak.lineFeed;
    scanner.skipCharAtCursor();
  }

  return maybeCR;
}

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
    toWrite = lineBreaks.length == 1
        ? [if (contentBuffer.isNotEmpty) WhiteSpace.space]
        : lineBreaks.skip(1);
  }

  contentBuffer.writeAll(toWrite.map((rc) => rc.string));
  lineBreaks.clear();
}

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
    startsWithTab = true;
    callBeforeTabWrite();
    contentBuffer.writeAll(
      scanner.skipWhitespace(skipTabs: true).map((t) => t.string),
    );

    // This line cannot be used to determine the
    if (scanner.peekCharAfterCursor() is LineBreak) {
      return (inferredIndent: null, startsWithTab: startsWithTab);
    }
  }

  return (inferredIndent: canBeIndent, startsWithTab: startsWithTab);
}

const _takeOrSkip = 1;
const _whitespace = WhiteSpace.space;

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
      : lineBreaks.take(_takeOrSkip).cast<ReadableChar>().followedBy(
            lineBreaks.skip(_takeOrSkip).expand(
              (value) sync* {
                yield _whitespace;
                yield value;
              },
            ),
          );
}
