part of 'yaml_document.dart';

typedef _MapPreflightInfo = ({
  ParserEvent event,
  bool hasProperties,
  bool isExplicitEntry,
  bool blockMapContinue,
  int? indentOnExit,
});

typedef _ParseExplicitInfo = ({
  bool shouldExit,
  bool hasIndent,
  int? inferredIndent,
  ParsedProperty parsedProperty,
  int laxIndent,
  int inlineIndent,
});

typedef _BlockNodeInfo = ({int? exitIndent, DocumentMarker docMarker});

const _BlockNodeInfo _emptyScanner = (
  exitIndent: null,
  docMarker: DocumentMarker.none,
);

typedef _BlockNodeGeneric<T> = ({_BlockNodeInfo nodeInfo, T delegate});

typedef _BlockNode<R> = _BlockNodeGeneric<ParserDelegate<R>>;

typedef _BlockMapEntry<R> = ({
  ParserDelegate<R>? key,
  ParserDelegate<R>? value,
});

typedef _BlockEntry<R> = _BlockNodeGeneric<_BlockMapEntry<R>>;

typedef _ImplicitBlockValue<R> = _BlockNodeGeneric<ParserDelegate<R>?>;

/// Throws an exception if the prospective [YamlSourceNode]
/// (a child of the root node or the root node itself) in the document being
/// parsed did not have an explicit directives end marker (`---`) or the
/// directives end marker (`---`) is present but no directives were parsed.
///
/// This method is only works for [ScalarStyle.plain]. Any other style is safe.
void _throwIfUnsafeForDirectiveChar(
  GraphemeScanner scanner, {
  required int indent,
  required bool hasDirectives,
}) {
  if (scanner.charAtCursor == directive && indent == 0 && !hasDirectives) {
    throwWithSingleOffset(
      scanner,
      message:
          '"%" cannot be used as the first non-whitespace character in a'
          ' non-empty content line',
      offset: scanner.lineInfo().current,
    );
  }
}

/// Returns `true` if the document starts on the same line as the directives
/// end marker (`---`) and must have a separation space between the last `-`
/// and the first valid document char. Throws an error if no separation space
/// is present, that is, a `\t` or whitespace.
///
/// `NOTE:` A document cannot start on the same line as document end marker
/// (`...`).
bool _docIsInMarkerLine(
  GraphemeScanner scanner, {
  required bool isDocStartExplicit,
}) {
  if (!isDocStartExplicit) return false;

  switch (scanner.charAtCursor) {
    // Document
    case null || lineFeed || carriageReturn:
      break;

    case space || tab:
      scanner
        ..skipWhitespace(skipTabs: true)
        ..skipCharAtCursor();
      break;

    default:
      throwWithSingleOffset(
        scanner,
        message: 'Expected a separation space after the directives end markers',
        offset: scanner.lineInfo().current,
      );
  }

  /// A comment spans the entire line to the end. It's just a line break in
  /// YAML with more steps
  return scanner.charAtCursor.isNotNullAnd(
    (c) => !c.isLineBreak() && c != comment,
  );
}

/// Updates the end offset of a [blockNode] (mapping/sequence) using its
/// undestructured [info]
void _blockNodeInfoEndOffset(
  ParserDelegate blockNode, {
  required GraphemeScanner scanner,
  required _BlockNodeInfo info,
}) => _blockNodeEndOffset(
  blockNode,
  scanner: scanner,
  hasDocEndMarkers: info.docMarker.stopIfParsingDoc,
  indentOnExit: info.exitIndent,
);

/// Updates the end offset of a [blockNode] (mapping/sequence) based on its
/// [indentOnExit]. If [hasDocEndMarkers] is `true`, the end offset is
/// the offset of the last `\n` (even if part of `\r\n`) before the
/// document end markers (`---` or `...`) `+1`.
void _blockNodeEndOffset(
  ParserDelegate blockNode, {
  required GraphemeScanner scanner,
  required bool hasDocEndMarkers,
  required int? indentOnExit,
}) => blockNode.updateEndOffset = _determineBlockEndOffset(
  scanner,
  hasDocEndMarkers: hasDocEndMarkers,
  indentOnExit: indentOnExit,
);

/// Returns the end offset of a block node based on its [indentOnExit]. If
/// [hasDocEndMarkers] is `true`, the end offset is the offset of the last `\n`
/// (even if part of `\r\n`) before the document end markers (`---` or `...`)
/// `+1`.
RuneOffset _determineBlockEndOffset(
  GraphemeScanner scanner, {
  required bool hasDocEndMarkers,
  required int? indentOnExit,
}) {
  if (!hasDocEndMarkers) {
    if (!scanner.canChunkMore) {
      scanner.skipCharAtCursor(); // Completely skip last char
      return scanner.lineInfo().current;
    }

    if (indentOnExit == null) {
      throw ArgumentError.value(
        indentOnExit,
        'indentOnExit',
        'A block node always ends after an indent change but found null',
      );
    }
  }

  // For both doc end chars and indent change. Reference start of line
  return scanner.lineInfo().start;
}
