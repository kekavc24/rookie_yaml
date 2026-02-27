import 'dart:math';

import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';

/// Callback for creating a document with the current parser's information.
typedef DocumentBuilder<Doc, R> =
    Doc Function(
      ParsedDirectives directives,
      DocumentInfo documentInfo,
      RootNode<R> rootNode,
    );

typedef GreedyPlain = ({RuneOffset start, String greedChars});

typedef _OnDocStart = void Function(int document);

const rootIndentLevel = seamlessIndentMarker + 1;

/// Throws an exception if the prospective [YamlSourceNode]
/// (a child of the root node or the root node itself) in the document being
/// parsed did not have an explicit directives end marker (`---`) or the
/// directives end marker (`---`) is present but no directives were parsed.
///
/// This method is only works for [ScalarStyle.plain]. Any other style is safe.
void _throwIfBlockUnsafe(
  SourceIterator iterator, {
  required int indent,
  required bool hasDirectives,
  required bool inlineWithDirectiveMarker,
}) {
  if (iterator.current == directive && indent == 0 && !hasDirectives) {
    throwWithSingleOffset(
      iterator,
      message:
          '"%" cannot be used as the first non-whitespace character in a'
          ' non-empty content line',
      offset: iterator.currentLineInfo.current,
    );
  } else if (inlineWithDirectiveMarker &&
      inferBlockEvent(iterator) is BlockCollectionEvent) {
    throwForCurrentLine(
      iterator,
      message:
          'A block collection cannot be declared on the same line as a'
          ' directive end marker',
    );
  }
}

/// A [YamlDocument] parser.
///
/// [Doc] represents the type for all documents to be parsed and [R] represents
/// a type for all nodes that will be parsed.
final class DocumentParser<Doc, R> {
  /// Creates a forward-parsing document parser that emits a document of type
  /// [Doc] which has nodes of type [R] or a subtype of [R]. Calling
  /// `this.parseNext()` parses a single [Doc] from the [iterator].
  ///
  /// The document [builder] constructs a [Doc] from the information collected
  /// after parsing a full YAML document. The [collectionFunction] is used to
  /// construct a YAML list/map whereas the [scalarFunction] is reserved for
  /// scalars. Any aliases are constructed with the [aliasFunction].
  /// [onMapDuplicate] will always be called when a duplicate key is
  /// encountered and contains the key's start and end offset.
  ///
  /// [triggers] can be used to provide specialized callbacks to some parser
  /// actions that may be used to track the parser's state or provide resolvers
  /// for these actions.
  ///
  /// A custom logging function may be provided via the [logger].
  DocumentParser(
    SourceIterator iterator, {
    required AliasFunction<R> aliasFunction,
    required YamlCollectionBuilder<R> collectionFunction,
    required ScalarFunction<R> scalarFunction,
    required ParserLogger logger,
    required MapDuplicateHandler onMapDuplicate,
    required this.builder,
    CustomTriggers? triggers,
  }) : _state = ParserState<R>(
         iterator,
         aliasFunction: aliasFunction,
         collectionBuilder: collectionFunction,
         scalarFunction: scalarFunction,
         logger: logger,
         onMapDuplicate: onMapDuplicate,
         triggers: triggers,
       ),
       _onDocReset = triggers?.onDocumentStart ?? ((_) {});

  /// Constructs the document after the node has been parsed completely.
  final DocumentBuilder<Doc, R> builder;

  /// The internal parser's state.
  final ParserState<R> _state;

  /// Called when a new document's parsing begins.
  final _OnDocStart _onDocReset;

  /// Parses the next [Doc] if present in the YAML string.
  ///
  /// `NOTE:` This advances the parsing forward and holds no reference to a
  /// previously parsed [Doc].
  (bool didParse, Doc? parsed) parseNext() {
    _state.reset();
    final ParserState(:iterator, :comments, :logger) = _state;

    if (iterator.isEOF) return (false, null);

    iterator.allowBOM(true);

    _onDocReset(_state.current);

    GreedyPlain? docMarkerGreedy;
    YamlDirective? version;
    var tags = <TagHandle, GlobalTag>{};
    var reserved = <ReservedDirective>[];

    var rootIndent = skipToParsableChar(
      iterator,
      onParseComment: comments.add,
      leadingAsIndent: !_state.docStartExplicit,
    );

    iterator.skipBOM();
    var rootInDirectiveEndLine = false;

    if (!_state.docStartExplicit && (rootIndent == null || rootIndent == 0)) {
      final (
        :yamlDirective,
        :globalTags,
        :reservedDirectives,
        :hasDirectiveEnd,
      ) = parseDirectives(
        iterator,
        onParseComment: comments.add,
        warningLogger: (message) => logger(false, message),
      );

      _state.hasDirectives =
          yamlDirective != null ||
          globalTags.isNotEmpty ||
          reservedDirectives.isNotEmpty;

      // When directives are absent, we may see dangling "---". Just to be sure,
      // confirm this wasn't the case.
      if (!hasDirectiveEnd &&
          iterator.current == blockSequenceEntry &&
          iterator.peekNextChar() == blockSequenceEntry) {
        var greedy = 0;
        final startOnMissing = iterator.currentLineInfo.current;

        final marker = checkForDocumentMarkers(
          iterator,
          onMissing: null,
          writer: (_) => ++greedy,
        );

        marker == DocumentMarker.directiveEnd
            ? _state.docStartExplicit = true
            : docMarkerGreedy = (
                start: startOnMissing,
                greedChars: '-' * greedy,
              );
      } else {
        _state.docStartExplicit = hasDirectiveEnd;
      }

      if (_state.docStartExplicit) {
        // Fast forward to the first ns-char (line break excluded)
        if (iterator.current.isWhiteSpace()) {
          skipWhitespace(iterator, skipTabs: true);
          iterator.nextChar();
        }

        rootIndent = null;
        rootInDirectiveEndLine =
            iterator.current != comment && !iterator.current.isLineBreak();
      }

      version = yamlDirective;
      tags = globalTags;
      reserved = reservedDirectives;
    }

    // YAML allows the secondary tag to be declared with custom global tag
    _state.globalTags.addAll(tags);

    // Why block info? YAML clearly has a favourite child and that is the
    // block(-like) styles. They are indeed a human friendly format. Also, the
    // doc end chars "..." and "---" exist in this format.
    NodeDelegate<R>? root;
    BlockInfo? rootInfo;

    // If we attempted to check for doc markers and found none
    if (docMarkerGreedy != null) {
      final (:start, :greedChars) = docMarkerGreedy;

      final (:blockInfo, :node) = parseBlockScalar(
        _state,
        event: ScalarEvent.startFlowPlain,
        blockParentIndent: null,
        minIndent: 0,
        indentLevel: rootIndentLevel,
        isImplicit: false,
        composeImplicitMap: true,
        composedMapIndent: 0,
        greedyOnPlain: greedChars,
        start: start,
        scalarProperty: null,
      );

      root = node;
      rootInfo = blockInfo;
    } else {
      rootIndent ??= skipToParsableChar(
        iterator,
        onParseComment: comments.add,
        leadingAsIndent: !rootInDirectiveEndLine,
      );

      _throwIfBlockUnsafe(
        iterator,
        indent: rootIndent ?? 0,
        hasDirectives: _state.hasDirectives,
        inlineWithDirectiveMarker: rootInDirectiveEndLine,
      );

      final (:blockInfo, :node) = parseBlockNode(
        _state,
        blockParentIndent: null, // No parent
        inferredFromParent: rootIndent,
        indentLevel: rootIndentLevel,
        laxBlockIndent: 0,
        fixedInlineIndent: 0,
        forceInlined: false,
        composeImplicitMap: !rootInDirectiveEndLine,
        canComposeMapIfMultiline: true,
      );

      root = node;
      rootInfo = blockInfo;
    }

    var docMarker = rootInfo.docMarker;

    if (!iterator.isEOF && !rootInfo.docMarker.stopIfParsingDoc) {
      // We must see document end chars and don't care how they are laid within
      // the document. At this point the document is or should be complete
      skipToParsableChar(iterator, onParseComment: comments.add);

      // We can safely look for doc end chars
      if (!iterator.isEOF) {
        var charBehind = 0;
        docMarker = checkForDocumentMarkers(
          iterator,
          onMissing: (b) => charBehind = b.length,
          throwIfDocEndInvalid: true,
        );

        if (!docMarker.stopIfParsingDoc) {
          throwWithApproximateRange(
            iterator,
            message:
                'Invalid node state. Expected to find document end "..."'
                ' or directive end chars "---" ',
            current: iterator.currentLineInfo.current,
            charCountBefore: iterator.hasNext
                ? max(charBehind - 1, 0)
                : charBehind,
          );
        }
      }

      final sourceInfo = iterator.currentLineInfo;

      root.nodeSpan.parsingEnd = docMarker.stopIfParsingDoc
          ? sourceInfo.start
          : sourceInfo.current;
    }

    _state.updateDocEndChars(docMarker);

    return (
      true,
      builder(
        (version: version, tags: tags.values, unknown: reserved),
        (
          index: _state.current,
          docType: YamlDocType.inferType(
            hasDirectives: _state.hasDirectives,
            isDocStartExplicit: _state.docStartExplicit,
          ),
          hasExplicitStart: _state.docStartExplicit,
          hasExplicitEnd: _state.docEndExplicit,
        ),
        (root: root.parsed(), comments: comments, anchors: _state.anchorNodes),
      ),
    );
  }
}
