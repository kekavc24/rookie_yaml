part of 'yaml_document.dart';

typedef GreedyPlain = ({RuneOffset start, String greedChars});

const rootIndentLevel = seamlessIndentMarker + 1;

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

/// A [YamlDocument] parser.
final class DocumentParser<R, S extends Iterable<R>, M extends Map<R, R?>> {
  DocumentParser(
    GraphemeScanner scanner, {
    required AliasFunction<R> aliasFunction,
    required ListFunction<R, S> listFunction,
    required MapFunction<R, M> mapFunction,
    required ScalarFunction<R> scalarFunction,
    required ParserLogger logger,
    required MapDuplicateHandler onMapDuplicate,
    List<Resolver>? resolvers,
  }) : _parserState = ParserState<R, S, M>(
         scanner,
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

    final ParserState(:scanner, :comments, :logger) = _parserState;

    if (!scanner.canChunkMore) return (false, null);

    GreedyPlain? docMarkerGreedy;
    YamlDirective? version;
    var tags = <TagHandle, GlobalTag>{};
    var reserved = <ReservedDirective>[];

    _parserState.docStartExplicit = _parserState.lastDocEndChars == '---';

    // If no directives end indicator, parse directives
    if (!_parserState.docStartExplicit) {
      final (
        :yamlDirective,
        :globalTags,
        :reservedDirectives,
        :hasDirectiveEnd,
      ) = parseDirectives(
        scanner,
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
          scanner.charAtCursor == blockSequenceEntry &&
          scanner.charAfter == blockSequenceEntry) {
        final startOnMissing = scanner.lineInfo().current;

        _parserState.docStartExplicit =
            checkForDocumentMarkers(
              scanner,
              onMissing: (c) {
                docMarkerGreedy = (
                  start: startOnMissing,
                  greedChars: c.map((e) => e.asString()).join(),
                );
              },
            ) ==
            DocumentMarker.directiveEnd;
      } else {
        _parserState.docStartExplicit = hasDirectiveEnd;
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
      final (:start, :greedChars) = docMarkerGreedy!;

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
      _parserState.rootInMarkerLine = _docIsInMarkerLine(
        scanner,
        isDocStartExplicit: _parserState.docStartExplicit,
      );

      var rootIndent = skipToParsableChar(
        scanner,
        onParseComment: comments.add,
        skipLeading: false,
      );

      _throwIfUnsafeForDirectiveChar(
        scanner,
        indent: rootIndent ?? 0,
        hasDirectives: _parserState.hasDirectives,
      );

      final (:blockInfo, :node) = parseBlockNode(
        _parserState,
        inferredFromParent: rootIndent,
        indentLevel: rootIndentLevel,
        laxBlockIndent: 0,
        fixedInlineIndent: 0,
        forceInlined: false,
        composeImplicitMap: true,
      );

      root = node;
      rootInfo = blockInfo;
    }

    var docMarker = DocumentMarker.none;

    if (scanner.canChunkMore) {
      /// We must see document end chars and don't care how they are laid within
      /// the document. At this point the document is or should be complete
      if (!rootInfo.docMarker.stopIfParsingDoc) {
        skipToParsableChar(scanner, onParseComment: comments.add);

        // We can safely look for doc end chars
        if (scanner.canChunkMore) {
          var charBehind = 0;
          docMarker = checkForDocumentMarkers(
            scanner,
            onMissing: (b) => charBehind = b.length,
          );

          if (!docMarker.stopIfParsingDoc) {
            throwWithApproximateRange(
              scanner,
              message:
                  'Expected to find document end chars "..." or directive end '
                  'chars "---" ',
              current: scanner.lineInfo().current,
              charCountBefore: scanner.canChunkMore
                  ? max(charBehind - 1, 0)
                  : charBehind,
            );
          }
        }

        final sourceInfo = scanner.lineInfo();

        root.updateEndOffset = docMarker.stopIfParsingDoc
            ? sourceInfo.start
            : sourceInfo.current;
      } else {
        docMarker = rootInfo.docMarker;
      }
    } else {
      docMarker = rootInfo.docMarker;
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
