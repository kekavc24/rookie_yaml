part of 'yaml_document.dart';

typedef GreedyPlain = ({RuneOffset start, String greedChars});

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
final class DocumentParser<R, S extends Iterable<R>, M extends Map<R, R?>> {
  DocumentParser(
    SourceIterator iterator, {
    required AliasFunction<R> aliasFunction,
    required ListFunction<R, S> listFunction,
    required MapFunction<R, M> mapFunction,
    required ScalarFunction<R> scalarFunction,
    required ParserLogger logger,
    required MapDuplicateHandler onMapDuplicate,
    List<Resolver>? resolvers,
  }) : _parserState = ParserState<R, S, M>(
         iterator,
         aliasFunction: aliasFunction,
         listFunction: listFunction,
         mapFunction: mapFunction,
         scalarFunction: scalarFunction,
         logger: logger,
         onMapDuplicate: onMapDuplicate,
         resolvers: resolvers,
       );

  final ParserState<R, S, M> _parserState;

  /// Parses the next [YamlDocument] if present in the YAML string.
  ///
  /// `NOTE:` This advances the parsing forward and holds no reference to a
  /// previously parsed [YamlDocument].
  (bool didParse, T? parsed) parseNext<T>() {
    _parserState.reset();

    final ParserState(:iterator, :comments, :logger) = _parserState;

    if (iterator.isEOF) return (false, null);

    GreedyPlain? docMarkerGreedy;
    YamlDirective? version;
    var tags = <TagHandle, GlobalTag>{};
    var reserved = <ReservedDirective>[];

    var rootIndent = skipToParsableChar(
      iterator,
      onParseComment: comments.add,
      leadingAsIndent: !_parserState.docStartExplicit,
    );

    var rootInDirectiveEndLine = false;

    if (!_parserState.docStartExplicit &&
        (rootIndent == null || rootIndent == 0)) {
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

      _parserState.hasDirectives =
          yamlDirective != null ||
          globalTags.isNotEmpty ||
          reservedDirectives.isNotEmpty;

      /// When directives are absent, we may see dangling "---". Just to be
      /// sure, confirm this wasn't the case.
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
            ? _parserState.docStartExplicit = true
            : docMarkerGreedy = (
                start: startOnMissing,
                greedChars: '-' * greedy,
              );
      } else {
        _parserState.docStartExplicit = hasDirectiveEnd;
      }

      if (_parserState.docStartExplicit) {
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
    _parserState.globalTags.addAll(tags);

    /// Why block info? YAML clearly has a favourite child and that is the
    /// block(-like) styles. They are indeed a human friendly format. Also, the
    /// doc end chars "..." and "---" exist in this format.
    ParserDelegate<R>? root;
    BlockInfo? rootInfo;

    /// If we attempted to check for doc markers and found none
    if (docMarkerGreedy != null) {
      final (:start, :greedChars) = docMarkerGreedy;

      final (:blockInfo, :node) = parseBlockScalar(
        _parserState,
        event: ScalarEvent.startFlowPlain,
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
        hasDirectives: _parserState.hasDirectives,
        inlineWithDirectiveMarker: rootInDirectiveEndLine,
      );

      final (:blockInfo, :node) = parseBlockNode(
        _parserState,
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
      /// We must see document end chars and don't care how they are laid within
      /// the document. At this point the document is or should be complete
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

      root.updateEndOffset = docMarker.stopIfParsingDoc
          ? sourceInfo.start
          : sourceInfo.current;
    }

    _parserState.updateDocEndChars(docMarker);

    return (
      true,
      switch (root.parsed()) {
        YamlSourceNode node =>
          YamlDocument._(
                _parserState.current,
                version,
                tags.values.toSet(),
                reserved,
                comments,
                node,
                YamlDocType.inferType(
                  hasDirectives: _parserState.hasDirectives,
                  isDocStartExplicit: _parserState.docStartExplicit,
                ),
                _parserState.docStartExplicit,
                _parserState.docEndExplicit,
              )
              as T,
        R object => object as T?,
      },
    );
  }
}
