import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Checks if the next block sequence entry is a valid entry or just a
/// directive end marker. Returns `null` if the next entry is a valid block
/// node. Otherwise, throws if the next node is not a
/// [DocumentMarker.directiveEnd].
DocumentMarker? _sequenceNodeOrMarker(GraphemeScanner scanner, int indent) {
  final current = scanner.charAtCursor;
  final next = scanner.charAfter;

  switch (current) {
    // Be gracious and check if we have doc end chars here
    case blockSequenceEntry || period when indent == 0 && next == current:
      {
        if (checkForDocumentMarkers(scanner, onMissing: (_) {})
            case DocumentMarker docType when docType.stopIfParsingDoc) {
          return docType;
        }

        continue invalid;
      }

    case blockSequenceEntry
        when next.isNullOr((c) => c.isWhiteSpace() || c.isLineBreak()):
      return null;

    invalid:
    default:
      throwForCurrentLine(
        scanner,
        message: 'Expected a "- " at the start of the next entry',
        end: scanner.lineInfo().current,
      );
  }
}

/// Parses a block sequence.
BlockNode<Obj>
parseBlockSequence<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  SequenceDelegate<Obj, Seq> sequence, {
  required ParserState<Obj, Seq, Dict> state,
}) {
  final ParserState(:scanner, :comments) = state;
  final SequenceDelegate(indent: sequenceIndent, :indentLevel) = sequence;

  final entryIndent = sequenceIndent + 1;
  final entryIndentLevel = indentLevel + 1;

  do {
    final indicatorOffset = scanner.lineInfo().current;
    scanner.skipCharAtCursor();

    /// Be mechanical. Call [parseBlockNode] only after we determine the
    /// correct indent range for this node.
    final indentOrSeparation = skipToParsableChar(
      scanner,
      onParseComment: comments.add,
    );

    if (indentOrSeparation != null && indentOrSeparation <= sequenceIndent) {
      sequence.accept(
        nullBlockNode(
          state,
          indentLevel: entryIndentLevel,
          indent: sequenceIndent + 1,
          start: scanner.canChunkMore
              ? scanner.lineInfo().start
              : scanner.lineInfo().current,
        ).parsed(),
      );

      if (indentOrSeparation < sequenceIndent) {
        return (
          blockInfo: (
            docMarker: DocumentMarker.none,
            exitIndent: indentOrSeparation,
          ),
          node: sequence as ParserDelegate<Obj>,
        );
      }
    } else {
      final (:laxIndent, :inlineFixedIndent) = indentOfBlockChild(
        indentOrSeparation,
        blockParentIndent: sequenceIndent,
        yamlNodeStartOffset: indicatorOffset.utfOffset,
        contentOffset: scanner.lineInfo().current.utfOffset,
      );

      final (:blockInfo, :node) = parseBlockNode(
        state,
        indentLevel: entryIndentLevel,
        inferredFromParent: indentOrSeparation,
        laxBlockIndent: entryIndent,
        fixedInlineIndent: inlineFixedIndent,
        forceInlined: false,
        composeImplicitMap: true,
      );

      sequence
        ..accept(node.parsed())
        ..updateEndOffset = node.endOffset
        ..hasLineBreak = node.encounteredLineBreak;

      final (:docMarker, :exitIndent) = blockInfo;

      if (!scanner.canChunkMore ||
          docMarker.stopIfParsingDoc ||
          (exitIndent != null && exitIndent < sequenceIndent)) {
        return (blockInfo: blockInfo, node: sequence as ParserDelegate<Obj>);
      } else if (exitIndent != null && exitIndent > sequenceIndent) {
        throwWithSingleOffset(
          scanner,
          message: 'Invalid block list entry found',
          offset: scanner.lineInfo().current,
        );
      }
    }

    // In case we see "---" or "..." before the next node
    if (_sequenceNodeOrMarker(scanner, sequenceIndent)
        case DocumentMarker marker) {
      return (
        blockInfo: (docMarker: marker, exitIndent: null),
        node: sequence as ParserDelegate<Obj>,
      );
    }
  } while (scanner.canChunkMore);

  return (blockInfo: emptyScanner, node: sequence as ParserDelegate<Obj>);
}
