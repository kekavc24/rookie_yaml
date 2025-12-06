import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Checks if the next block sequence entry is a valid entry or just a
/// directive end marker. Returns `null` if the next entry is a valid block
/// node. Otherwise, throws if the next node is not a
/// [DocumentMarker.directiveEnd].
DocumentMarker? _sequenceNodeOrMarker(SourceIterator iterator, int indent) {
  final current = iterator.current;
  final next = iterator.peekNextChar();

  switch (current) {
    // Be gracious and check if we have doc end chars here
    case blockSequenceEntry || period when indent == 0 && next == current:
      {
        if (checkForDocumentMarkers(iterator, onMissing: (_) {})
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
        iterator,
        message: 'Expected a "- " at the start of the next entry',
        end: iterator.currentLineInfo.current,
      );
  }
}

/// Parses a block sequence.
BlockNode<Obj>
parseBlockSequence<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  SequenceDelegate<Obj, Seq> sequence, {
  required ParserState<Obj, Seq, Dict> state,
}) {
  final ParserState(:iterator, :comments) = state;
  final SequenceDelegate(indent: sequenceIndent, :indentLevel) = sequence;

  final entryIndent = sequenceIndent + 1;
  final entryIndentLevel = indentLevel + 1;

  do {
    final indicatorOffset = iterator.currentLineInfo.current;
    iterator.nextChar();

    /// Be mechanical. Call [parseBlockNode] only after we determine the
    /// correct indent range for this node.
    final indentOrSeparation = skipToParsableChar(
      iterator,
      onParseComment: comments.add,
    );

    if (indentOrSeparation != null && indentOrSeparation <= sequenceIndent) {
      final empty = nullBlockNode(
        state,
        indentLevel: entryIndentLevel,
        indent: sequenceIndent + 1,
        start: iterator.isEOF
            ? iterator.currentLineInfo.current
            : iterator.currentLineInfo.start,
      );

      sequence
        ..accept(empty.parsed())
        ..updateEndOffset = empty.endOffset;

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
        contentOffset: iterator.currentLineInfo.current.utfOffset,
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

      if (iterator.isEOF ||
          docMarker.stopIfParsingDoc ||
          (exitIndent != null && exitIndent < sequenceIndent)) {
        return (blockInfo: blockInfo, node: sequence as ParserDelegate<Obj>);
      } else if (exitIndent != null && exitIndent > sequenceIndent) {
        throwWithSingleOffset(
          iterator,
          message: 'Invalid block list entry found',
          offset: iterator.currentLineInfo.current,
        );
      }
    }

    // In case we see "---" or "..." before the next node
    if (_sequenceNodeOrMarker(iterator, sequenceIndent)
        case DocumentMarker marker) {
      return (
        blockInfo: (docMarker: marker, exitIndent: null),
        node: sequence as ParserDelegate<Obj>,
      );
    }
  } while (!iterator.isEOF);

  return (
    blockInfo: emptyScanner,
    node:
        (sequence..updateEndOffset = iterator.currentLineInfo.current)
            as ParserDelegate<Obj>,
  );
}
