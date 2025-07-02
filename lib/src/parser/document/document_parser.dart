part of 'yaml_document.dart';

typedef _ParsedDocDirectives = ({
  bool isDocEnd,
  YamlDirective? yamlDirective,
  Map<TagHandle, GlobalTag> globalTags,
  List<ReservedDirective> reservedDirectives,
});

final _defaultGlobalTag = MapEntry(TagHandle.secondary(), yamlGlobalTag);

final class DocumentParser {
  DocumentParser(this._scanner);

  /// Scanner with source string
  final ChunkScanner _scanner;

  /// Global directives.
  ///
  /// Secondary tag always resolves
  final _globalTags = Map.fromEntries([_defaultGlobalTag]);

  /// Index of document being parsed
  int _currentIndex = -1;

  /// Char sequence that terminated the last document.
  ///
  /// If `...`, the parser looks for directives first before parsing can
  /// start until an explicit `---` is encountered. Throws an error otherwise.
  ///
  /// If `---`, the parser starts parsing nodes immediately. This also limits
  /// the use of `%` as the first character for plain style-like nodes, that is,
  /// [ScalarStyle.plain], [ScalarStyle.literal] and [ScalarStyle.folded]. The
  /// character cannot be used if the indent level is `0`.
  String _lastWasDocEndChars = '';

  /// Tracks if the current document has an explicit start.
  ///
  /// End of directives. `---` at beginning.
  bool _docStartExplicit = false;

  /// Tracks if last document had an explicit end.
  ///
  /// `...` at the end.
  bool _docEndExplicit = false;

  /// Tracks whether the root node start on the same line as the directives
  /// end marker (`---`).
  bool _rootInMarkerLine = false;

  /// Tracks whether any directives were declared
  bool _hasDirectives = false;

  final _greedyChars = <ReadableChar>[];

  final _anchorNodes = <String, ParserDelegate>{};

  SplayTreeSet<YamlComment> _comments = SplayTreeSet();

  bool _keyIsJsonLike(ParserDelegate? delegate) {
    /// Flow node with indicators:
    ///   - Single & double quoted scalars
    ///   - Flow map & sequence
    return switch (delegate) {
      ScalarDelegate(
        preScalar: PreScalar(
          scalarStyle: ScalarStyle.singleQuoted || ScalarStyle.doubleQuoted,
        ),
      ) ||
      CollectionDelegate(collectionStyle: NodeStyle.flow) => true,
      _ => false,
    };
  }

  void _restartParser() {
    ++_currentIndex; // Move to next document

    if (_currentIndex == 0) return;

    _hasDirectives = false;
    _docStartExplicit = false;
    _docEndExplicit = false;

    _rootInMarkerLine = false;

    _globalTags
      ..clear()
      ..addEntries([_defaultGlobalTag]);

    _greedyChars.clear();
    _anchorNodes.clear();
    _comments = SplayTreeSet();
  }

  void _updateDocEndChars(String docEndChars) {
    _lastWasDocEndChars = docEndChars;
    _docEndExplicit = docEndChars == '...';

    if (_scanner.charAtCursor
        case LineBreak _ || WhiteSpace _ || Indicator.comment
        when _docEndExplicit) {
      _skipToParsableChar(_scanner, comments: _comments);
    }
  }

  /// Parses directives and any its end marker if present
  _ParsedDocDirectives _processDirectives() {
    final (:yamlDirective, :globalTags, :reservedDirectives) = parseDirectives(
      _scanner,
    );

    var hasDocMarker = false;

    final charAtCursor = _scanner.charAtCursor;

    if (charAtCursor == Indicator.period ||
        (charAtCursor == Indicator.blockSequenceEntry &&
            _scanner.peekCharAfterCursor() == Indicator.blockSequenceEntry)) {
      hasDocMarker = hasDocumentMarkers(
        _scanner,
        onMissing: (greedy) => _greedyChars.addAll(greedy),
      );

      if (hasDocMarker) {
        _docStartExplicit = _inferDocEndChars(_scanner) == '---';
      }
    }

    _hasDirectives =
        yamlDirective != null ||
        globalTags.isNotEmpty ||
        reservedDirectives.isNotEmpty;

    /// Must have explicit directive end if directives are present or just a
    /// document end to terminate the current document after its directives
    if (_hasDirectives && !(_docStartExplicit || hasDocMarker)) {
      throw FormatException(
        'Expected the directive end marker [---] after declaring directives',
      );
    }

    return (
      isDocEnd: !_docStartExplicit && hasDocMarker,
      yamlDirective: yamlDirective,
      globalTags: globalTags,
      reservedDirectives: reservedDirectives,
    );
  }

  /// Resolves a local tag to a global tag uri if present.
  ResolvedTag _resolveTag(LocalTag localTag) {
    final LocalTag(:tagHandle, :content) = localTag;

    SpecificTag tag = localTag;
    var suffix = ''; // Local tags have no suffixes

    // Check if alias to global tag
    final globalTag = _globalTags[tag.tagHandle];
    final hasGlobalTag = globalTag != null;

    // A named tag must have a corresponding global tag
    if (tagHandle.handleVariant == TagHandleVariant.named && !hasGlobalTag) {
      throw FormatException(
        'Tags with named shorthands must have a corresponding global tag',
      );
    } else if (hasGlobalTag) {
      tag = globalTag;
      suffix = content; // Local tag is prefixed with global tag uri
    }

    return ParsedTag(tag, suffix);
  }

  /// Parses the next [YamlDocument] if present in the YAML string.
  ///
  /// `NOTE:` This advances the parsing forward and holds no reference to a
  /// previously parsed [YamlDocument].
  YamlDocument? parseNext() {
    _restartParser();

    if (!_scanner.canChunkMore) return null;

    YamlDirective? version;
    var tags = <TagHandle, GlobalTag>{};
    var reserved = <ReservedDirective>[];

    _docStartExplicit = _lastWasDocEndChars == '---';

    // If no directives end indicator, parse directives
    if (!_docStartExplicit) {
      final (:isDocEnd, :yamlDirective, :globalTags, :reservedDirectives) =
          _processDirectives();

      if (isDocEnd) {
        _updateDocEndChars('.'.padRight(3, '.'));
        return YamlDocument._(
          _currentIndex,
          yamlDirective,
          globalTags.values.toSet(),
          reservedDirectives,
          _comments,
          null,
          YamlDocType.inferType(
            hasDirectives: _hasDirectives,
            isDocStartExplicit: _docStartExplicit,
          ),
          _docStartExplicit,
          _docEndExplicit,
        );
      }

      version = yamlDirective;
      tags = globalTags;
      reserved = reservedDirectives;
    }

    // YAML allows the secondary tag to be declared with custom global tag
    _globalTags.addAll(tags);

    _rootInMarkerLine = _docIsInMarkerLine(
      _scanner,
      isDocStartExplicit: _docStartExplicit,
    );

    final (:foundDocEndMarkers, :rootEvent, :rootDelegate) = _parseNodeAtRoot(
      _scanner,
      rootInMarkerLine: _rootInMarkerLine,
      isDocStartExplicit: _docStartExplicit,
      hasDirectives: _hasDirectives,
      comments: _comments,
      greedyChars: _greedyChars.map((c) => c.string),
    );

    var event = rootEvent;
    var root = rootDelegate;
    ParserDelegate? keyIfMap;

    /// Further verify if the scalar parsed on a single line is a key or just
    /// a scalar on a single line
    if (rootDelegate is ScalarDelegate) {
      var isInlineScalar = true;

      if (!foundDocEndMarkers) {
        // Move to the next parsable character
        switch (_skipToParsableChar(_scanner, comments: _comments)) {
          // No more characters. This is the last document.
          case null when !_scanner.canChunkMore:
            break;

          // Convert to key delegate ready to parse a map
          case null
              when _inferNextEvent(
                    _scanner,
                    isBlockContext: true,
                    lastKeyWasJsonLike: false,
                  ) ==
                  BlockCollectionEvent.startEntryValue:
            {
              isInlineScalar = false;
              final ScalarDelegate(:startOffset, :indent) = rootDelegate;

              event = BlockCollectionEvent.startImplicitKey;
              keyIfMap = rootDelegate;
              root = MappingDelegate(
                collectionStyle: NodeStyle.block,
                indentLevel: 0,
                indent: indent,
                startOffset: startOffset,
                blockTags: {},
                inlineTags: {},
                blockAnchors: {},
                inlineAnchors: {},
              );
            }

          default:
            {
              if (_scanner.charAtCursor case LineBreak char) {
                skipCrIfPossible(char, scanner: _scanner);
                _scanner.skipCharAtCursor();
              }

              // Check for document/directive end marker
              if (!hasDocumentMarkers(_scanner, onMissing: (_) {})) {
                throw FormatException(
                  'Expected a directive/document end marker after parsing'
                  ' scalar',
                );
              }
            }
        }
      }

      if (isInlineScalar) {
        if (_scanner.canChunkMore) {
          _updateDocEndChars(_inferDocEndChars(_scanner));
        }

        return YamlDocument._(
          _currentIndex,
          version,
          tags.values.toSet(),
          reserved,
          _comments,
          rootDelegate.parsed(),
          YamlDocType.inferType(
            hasDirectives: _hasDirectives,
            isDocStartExplicit: _docStartExplicit,
          ),
          _docStartExplicit,
          _docEndExplicit,
        );
      }
    }

    /// Why block info? YAML clearly has a favourite child and that is the
    /// block(-like) styles. They are indeed a human friendly format. Also, the
    /// doc end chars "..." and "---" exist in this format.
    _BlockNodeInfo? rootInfo;

    switch (event) {
      // Start of flow map or sequence. Never inlined ahead of time.
      case FlowCollectionEvent event:
        {
          event == FlowCollectionEvent.startFlowMap
              ? _parseFlowMap(root as MappingDelegate, forceInline: false)
              : _parseFlowSequence(
                  root as SequenceDelegate,
                  forceInline: false,
                );

          final ParserDelegate(:indent, :startOffset, :encounteredLineBreak) =
              root;

          /// As indicated initially, YAML considerably favours block(-like)
          /// styles. This flow collection may be an implicit key if only it
          /// is inline and we see a ": " char combination ahead.
          if (!encounteredLineBreak &&
              _skipToParsableChar(
                    _scanner,
                    comments: _comments,
                  ) ==
                  null &&
              _inferNextEvent(
                    _scanner,
                    isBlockContext: true,
                    lastKeyWasJsonLike: false,
                  ) ==
                  BlockCollectionEvent.startEntryValue) {
            keyIfMap = root;
            root = MappingDelegate(
              collectionStyle: NodeStyle.block,
              indentLevel: 0,
              indent: indent,
              startOffset: startOffset,
              blockTags: {},
              inlineTags: {},
              blockAnchors: {},
              inlineAnchors: {},
            );

            continue blockMap; // Executes without eval. Sure bet!
          }
        }

      case BlockCollectionEvent.startBlockListEntry:
        rootInfo = _parseBlockSequence(root as SequenceDelegate);

      // Versatile and unpredictable
      blockMap:
      case BlockCollectionEvent.startExplicitKey ||
          BlockCollectionEvent.startImplicitKey ||
          BlockCollectionEvent.startEntryValue:
        rootInfo = _parseBlockMap(root as MappingDelegate, keyIfMap);

      // Should never be the case
      default:
        throw Exception('[Parser Error]: Unhandled parser event: "$event"');
    }

    if (_scanner.canChunkMore) {
      /// We must see document end chars and don't care how they are laid within
      /// the document
      if (rootInfo == null || !rootInfo.hasDocEndMarkers) {
        _skipToParsableChar(_scanner, comments: _comments);

        final fauxBuffer = <String>[];

        if (_scanner.canChunkMore &&
            !hasDocumentMarkers(
              _scanner,
              onMissing: (b) => fauxBuffer.addAll(b.map((e) => e.string)),
            )) {
          throw FormatException(
            'Expected to find document end chars "..." or directive end chars '
            '"---" but found ${fauxBuffer.join()}',
          );
        }
      }

      _updateDocEndChars(_inferDocEndChars(_scanner));
    }

    return YamlDocument._(
      _currentIndex,
      version,
      tags.values.toSet(),
      reserved,
      _comments,
      root.parsed(),
      YamlDocType.inferType(
        hasDirectives: _hasDirectives,
        isDocStartExplicit: _docStartExplicit,
      ),
      _docStartExplicit,
      _docEndExplicit,
    );
  }

  /// Skips to the next parsable flow indicator/character.
  ///
  /// If declared on a new line and [forceInline] is `false`, the flow
  /// indicator/character must be indented at least [minIndent] spaces. Throws
  /// otherwise.
  bool _nextLineSafeInFlow(int minIndent, {required bool forceInline}) {
    final indent = _skipToParsableChar(_scanner, comments: _comments);

    if (indent != null) {
      // Must not have line breaks
      if (forceInline) {
        throw FormatException(
          'Found a line break when parsing a flow node just before '
          '${_scanner.currentOffset}',
        );
      }

      /// If line breaks are allowed, it must at least be the same or
      /// greater than the min indent. Indent serves no purpose in flow
      /// collections. The min indent is for respecting the parent block
      /// collection
      if (indent < minIndent) {
        throw FormatException(
          'Expected at ${minIndent - indent} additional spaces but found:'
          ' ${_scanner.charAtCursor}',
        );
      }
    } else if (!_scanner.canChunkMore) {
      return false;
    }

    return true;
  }

  /// Throws if the current char doesn't match the flow collection [delimiter]
  void _throwIfNotFlowDelimiter(Indicator delimiter) {
    _skipToParsableChar(_scanner, comments: _comments);

    final char = _scanner.charAtCursor;

    if (char != delimiter) {
      throw FormatException(
        'Expected the flow delimiter: $delimiter "${delimiter.string}" but'
        ' found: "${char?.string ?? 'nothing'}"',
      );
    }

    _scanner.skipCharAtCursor(); // Skip it if valid
  }

  /// Parses a flow map.
  ///
  /// If [forceInline] is `true`, the map must be declared on the same line
  /// with no line breaks and throws if otherwise.
  void _parseFlowMap(MappingDelegate delegate, {required bool forceInline}) {
    _throwIfNotFlowDelimiter(Indicator.mappingStart);

    final MappingDelegate(:indent, :indentLevel) = delegate;
    const mapEnd = Indicator.mappingEnd;

    while (_scanner.canChunkMore) {
      final (key, value) = _parseFlowMapEntry(
        null,
        indentLevel: indentLevel,

        /// As per YAML, no need forcing indentation in flow map as long as it
        /// adheres to the minimum indent set by block parent if in block
        /// context. If in flow context, let it "flow" and lay itself!
        minIndent: indent,
        forceInline: forceInline,
        exitIndicator: mapEnd,
      );

      /// If our key is null, it means no parsing occured. The
      /// [_parseFlowMapEntry] guarantees that it will return a wrapped null
      /// key when no key was parsed.
      if (key == null) break;

      // Map already contains key
      if (!delegate.pushEntry(key, value)) {
        // TODO: Show next key to help user know which key!
        // TODO: Inline the key if too long
        throw FormatException(
          'Flow map cannot contain duplicate entries by the same key',
        );
      }

      if (!_nextLineSafeInFlow(indent, forceInline: forceInline)) break;

      // Only continues if current non-space character is a ","
      if (_scanner.charAtCursor case Indicator.flowEntryEnd) {
        _scanner.skipCharAtCursor();
        continue;
      }

      break; // Always assume we are ending the parsing if not continuing!
    }

    _throwIfNotFlowDelimiter(mapEnd);
  }

  /// Parse a flow sequence/list.
  ///
  /// If [forceInline] is `true`, the list must be declared on the same line
  /// with no line breaks and throws if otherwise.
  void _parseFlowSequence(
    SequenceDelegate delegate, {
    required bool forceInline,
  }) {
    _throwIfNotFlowDelimiter(Indicator.flowSequenceStart);

    final SequenceDelegate(:indent, :indentLevel) = delegate;
    const seqEnd = Indicator.flowSequenceEnd;

    listParser:
    while (_scanner.canChunkMore) {
      // Always ensure we are at a parsable char. Safely.
      if (!_nextLineSafeInFlow(indent, forceInline: forceInline)) break;

      final charAfter = _scanner.peekCharAfterCursor();

      // We will always have a char here
      switch (_scanner.charAtCursor) {
        case Indicator.flowEntryEnd:
          {
            final exception = delegate.isEmpty
                ? FormatException(
                    'Expected to find the first value but found ","',
                  )
                : FormatException(
                    'Found a duplicate "," before finding a flow sequence '
                    'entry',
                  );

            throw exception;
          }

        // Parse explicit key
        case Indicator.mappingKey
            when charAfter == WhiteSpace.space ||
                flowDelimiters.contains(charAfter):
          {
            final (key, value) = _parseFlowMapEntry(
              null,
              indentLevel: indentLevel,
              minIndent: indent,
              forceInline: forceInline,
              exitIndicator: seqEnd,
            );

            /// The key cannot be null since we know it is explicit.
            /// [_parseFlowMapEntry] will wrap it in a null key. However, for
            /// null safety, just check
            if (key == null) break listParser;

            delegate.pushEntry(
              MapEntryDelegate(nodeStyle: NodeStyle.flow, keyDelegate: key)
                ..valueDelegate = value
                ..hasLineBreak =
                    key.encounteredLineBreak ||
                    (value?.encounteredLineBreak ?? false),
            );
          }

        case seqEnd:
          break listParser;

        default:
          {
            // Handles all flow node types i.e map, sequence and scalars
            final keyOrElement = _parseFlowNode(
              isParsingKey: false,
              currentIndentLevel: indentLevel,
              minIndent: indent,
              forceInline: forceInline,
              isExplicitKey: false,
              keyIsJsonLike: false,
              collectionDelimiter: seqEnd,
            );

            // Go to the next parsable char
            if (!_nextLineSafeInFlow(indent, forceInline: forceInline)) {
              break listParser;
            }

            /// Normally a list is a wildcard. We must assume that we parsed
            /// an implicit key unless we never see ":". Encountering a
            /// linebreak means the current flow node cannot be an implicit key.
            ///
            /// YAML requires us to treat all keys as implicit unless explicit
            /// which are normally restricted to a single line.
            if (keyOrElement.encounteredLineBreak ||
                _inferNextEvent(
                      _scanner,
                      isBlockContext: false,
                      lastKeyWasJsonLike: _keyIsJsonLike(keyOrElement),
                    ) !=
                    FlowCollectionEvent.startEntryValue) {
              delegate.pushEntry(keyOrElement);
              break;
            }

            // We have the key. No need for it!
            final (_, value) = _parseFlowMapEntry(
              keyOrElement,
              indentLevel: indentLevel,
              minIndent: indent,
              forceInline: forceInline,
              exitIndicator: seqEnd,
            );

            delegate.pushEntry(
              MapEntryDelegate(
                  nodeStyle: NodeStyle.flow,
                  keyDelegate: keyOrElement,
                )
                ..valueDelegate = value
                ..hasLineBreak =
                    keyOrElement.encounteredLineBreak ||
                    (value?.encounteredLineBreak ?? false),
            );
          }
      }

      if (!_nextLineSafeInFlow(indent, forceInline: forceInline)) break;

      // Must see "]" or ","
      switch (_scanner.charAtCursor) {
        case Indicator.flowEntryEnd:
          _scanner.skipCharAtCursor();

        case seqEnd:
          break listParser;

        default:
          throw FormatException(
            'Expected to find a flow entry end indicator ","'
            ' or flow sequence end "]" but'
            ' found ${_scanner.charAtCursor?.string}',
          );
      }
    }

    _throwIfNotFlowDelimiter(seqEnd);
  }

  /// Parses a single flow map entry.
  (ParserDelegate? key, ParserDelegate? value) _parseFlowMapEntry(
    ParserDelegate? key, {
    required int indentLevel,
    required int minIndent,
    required bool forceInline,
    required Indicator exitIndicator,
  }) {
    var parsedKey = key;
    ParserDelegate? value;

    if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline) ||
        _scanner.charAtCursor == exitIndicator) {
      return (key, value);
    }

    /// You may notice an intentional syntax change to how nodes are being
    /// parsed, that is, limited use of [ParserEvent]. This is because the
    /// scope is limited when actual parsing is being done. We don't need
    /// events here to know what fine grained action we need to do.

    if (_scanner.charAtCursor case Indicator.flowEntryEnd) {
      throw FormatException(
        'Expected at least a key in the flow map entry but found ","',
      );
    }

    parsedKey ??= _parseFlowNode(
      isParsingKey: true,
      currentIndentLevel: indentLevel,
      minIndent: minIndent,
      forceInline: forceInline,

      /// Defaults to false. The function will recursively infer internally
      /// if `true` and act accordingly
      isExplicitKey: false,
      keyIsJsonLike: false,
      collectionDelimiter: exitIndicator,
    );

    final keyIsJsonLike = _keyIsJsonLike(parsedKey);

    final expectedCharErr = FormatException(
      'Expected a next flow entry indicator "," or a map value indicator ":" '
      'or a terminating delimiter "${exitIndicator.string}"',
    );

    if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline)) {
      throw expectedCharErr;
    }

    /// Checks if we should parse a value or ignore it
    bool ignoreValue(ReadableChar? char) {
      return char == null ||
          char == Indicator.flowEntryEnd ||
          char == exitIndicator;
    }

    // Check if this is the start of a flow value
    if (_inferNextEvent(
          _scanner,
          isBlockContext: false,
          lastKeyWasJsonLike: keyIsJsonLike,
        ) ==
        FlowCollectionEvent.startEntryValue) {
      _scanner.skipCharAtCursor();

      if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline)) {
        throw expectedCharErr;
      }

      if (!ignoreValue(_scanner.charAtCursor)) {
        value = _parseFlowNode(
          isParsingKey: false,
          currentIndentLevel: indentLevel + 1, // One level deeper than key
          minIndent: minIndent,
          forceInline: forceInline,
          isExplicitKey: false,
          keyIsJsonLike: keyIsJsonLike,
          collectionDelimiter: exitIndicator,
        );
      }
    } else if (!ignoreValue(_scanner.charAtCursor)) {
      // Must at least be end of parser, "," and ["}" if map or "]" if list
      throw expectedCharErr;
    }

    return (parsedKey, value);
  }

  /// Parses a flow node, that is, a map/sequence/scalar.
  ParserDelegate _parseFlowNode({
    required bool isParsingKey,
    required int currentIndentLevel,
    required int minIndent,
    required bool forceInline,
    required bool isExplicitKey,
    required bool keyIsJsonLike,
    required Indicator collectionDelimiter,
    bool isBlockContext = false, // Block styles should override
    ParserEvent? inferredEvent,
  }) {
    final event =
        inferredEvent ??
        _inferNextEvent(
          _scanner,
          isBlockContext: false,
          lastKeyWasJsonLike: keyIsJsonLike,
        );

    if (!event.isFlowContext) {
      throw Exception(
        'Expected a flow node but found a block node indicator:'
        ' ${_scanner.charAtCursor}',
      );
    }

    final isImplicitKey = isParsingKey && !isExplicitKey;

    switch (event) {
      case FlowCollectionEvent.startEntryValue when isParsingKey:
        return nullScalarDelegate(
          indentLevel: currentIndentLevel,
          indent: minIndent,
        );

      case FlowCollectionEvent.startExplicitKey:
        {
          _scanner.skipCharAtCursor();

          if (!_nextLineSafeInFlow(
            minIndent,
            forceInline: forceInline,
          )) {
            throw FormatException(
              'Invalid indent when parsing explicit flow key',
            );
          }

          final char = _scanner.charAtCursor;

          if (char == Indicator.flowEntryEnd || char == collectionDelimiter) {
            return nullScalarDelegate(
              indentLevel: currentIndentLevel,
              indent: minIndent,
            );
          }

          return _parseFlowNode(
            isParsingKey: isParsingKey,
            currentIndentLevel: currentIndentLevel,
            minIndent: minIndent,
            forceInline: forceInline,
            isExplicitKey: true,
            keyIsJsonLike: keyIsJsonLike,
            collectionDelimiter: collectionDelimiter,
          );
        }

      case FlowCollectionEvent.startFlowMap:
        {
          final map = MappingDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: currentIndentLevel + 1,
            indent: minIndent,
            startOffset: _scanner.currentOffset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          _parseFlowMap(map, forceInline: forceInline || isImplicitKey);
          return map;
        }

      case FlowCollectionEvent.startFlowSequence:
        {
          final sequence = SequenceDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: currentIndentLevel + 1,
            indent: minIndent,
            startOffset: _scanner.currentOffset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          _parseFlowSequence(
            sequence,
            forceInline: forceInline || isImplicitKey,
          );
          return sequence;
        }

      case ScalarEvent _:
        {
          final (prescalar, delegate) = _parseScalar(
            event,
            isImplicit: forceInline || isImplicitKey,
            isInFlowContext: true,
            indentLevel: currentIndentLevel,
            minIndent: minIndent,
          );

          /// Plain scalars can have document/directive end chars embedded
          /// in the content. If not implicit, it can be affected by indent
          /// changes since it has a block-like structure
          if (prescalar case PreScalar(
            scalarStyle: ScalarStyle.plain,
            :final indentOnExit,
            :final indentDidChange,
            :final hasDocEndMarkers,
          ) when !isImplicitKey || !forceInline) {
            // Flow node only ends after parsing a flow delimiter
            if (hasDocEndMarkers) {
              throw FormatException(
                "Premature document termination when parsing flow map entry.",
              );
            }

            // Must not detect an indent change less than flow indent
            if (indentDidChange && indentOnExit < minIndent) {
              throw FormatException(
                'Indent change detected when parsing plain scalar. Expected'
                ' $minIndent spaced but found $indentOnExit spaces',
              );
            }
          }

          return delegate;
        }

      case FlowCollectionEvent.nextFlowEntry
          when !isBlockContext && (!isParsingKey || isExplicitKey):
        {
          return nullScalarDelegate(
            indentLevel: currentIndentLevel,
            indent: minIndent,
          );
        }

      default:
        throw FormatException(
          '[Parser Error]: Should not be parsing flow node here',
        );
    }
  }

  /// Parses a [Scalar].
  (PreScalar scalar, ScalarDelegate delegate) _parseScalar(
    ScalarEvent event, {
    required bool isImplicit,
    required bool isInFlowContext,
    required int indentLevel,
    required int minIndent,
  }) {
    final startOffset = _scanner.currentOffset;

    final prescalar = switch (event) {
      ScalarEvent.startBlockLiteral || ScalarEvent.startBlockFolded
          when !isImplicit || !isInFlowContext =>
        parseBlockStyle(
          _scanner,
          minimumIndent: minIndent,
          onParseComment: _comments.add,
        ),

      ScalarEvent.startFlowDoubleQuoted => parseDoubleQuoted(
        _scanner,
        indent: minIndent,
        isImplicit: isImplicit,
      ),

      ScalarEvent.startFlowSingleQuoted => parseSingleQuoted(
        _scanner,
        indent: minIndent,
        isImplicit: isImplicit,
      ),

      // We are aware of what character is at the start. Cannot be null
      ScalarEvent.startFlowPlain => parsePlain(
        _scanner,
        indent: minIndent,
        charsOnGreedy: '',
        isImplicit: isImplicit,
        isInFlowContext: isInFlowContext,
      ),

      _ => throw FormatException(
        'Failed to parse block scalar as it can never be implicit or used in a'
        ' flow context!',
      ),
    };

    /// This is a failsafe. Every map/list (flow or block) must look for
    /// ways to ensure a `null` plain scalar is never returned. This ensures
    /// the internal parsing logic for parsing the map/list is correct. Each
    /// flow/block map/list handles missing values differently.
    ///
    /// TODO: Fix later. Wrap while parsing plain scalar?
    /// TODO(cont): If fixing, consider how this null is handled by each
    /// TODO(cont): flow/block collection beforehand
    if (prescalar == null) {
      throw FormatException('Null was returned when parsing a plain scalar!');
    }

    return (
      prescalar,
      ScalarDelegate(
        indentLevel: indentLevel,
        indent: minIndent,
        startOffset: startOffset,
        blockTags: {},
        inlineTags: {},
        blockAnchors: {},
        inlineAnchors: {},
      )..scalar = prescalar,
    );
  }

  /// Calculates the indent for a block node within a block collection
  /// only if [inferred] indent is null.
  ({int laxIndent, int inlineFixedIndent}) _blockChildIndent(
    int? inferred, {
    required int blockParentIndent,
    required int startOffset,
  }) {
    if (inferred != null) {
      return (laxIndent: inferred, inlineFixedIndent: inferred);
    }

    /// The calculation applies for the "?" and ":" as the both have to
    /// have the same indent since the ":" *MUST* be declared on a new line
    /// for block explicit keys.
    ///
    /// If null, that is, on the same line as the indicator:
    ///   - [isLax] indicates the child is okay being indented at least "+1".
    ///     This applies to [ScalarStyle.literal] and [ScalarStyle.folded].
    ///     Flow collections also benefit from this as the indent serves no
    ///     purpose other than respecting the current block parent's
    ///     indentation.
    ///   - Otherwise, we force a fixed indent/layout based on the character
    ///     difference upto the current parsable char. Forcing it to be aligned
    ///     if the node spills over into the next line. This may be seen with
    ///     block sequences and maps nested in a block sequence entry
    ///
    /// (meh! No markdown hover)
    /// ```yaml
    ///
    /// # With flow. Okay
    /// ? [
    ///  "blah", "blah",
    ///  "blah"]
    ///
    /// # With literal. Applies to folded. Okay
    /// ? |
    ///  block
    ///
    /// # With literal. Applies to folded. We give "+1". Indent determined
    /// # while parsing as recommended by YAML. See [parseBlockStyle]
    /// ? |
    ///     block
    ///
    /// # With block sequences. Must do this for okay
    /// ? - blah
    ///   - blah
    ///
    /// # With implicit or explict map
    /// ? key:
    ///   ? keey
    ///   : value
    ///
    /// # With block sequence. If this is done. Still okay. Inferred.
    /// ?
    ///  - blah
    ///  - blah
    ///
    /// ```
    return (
      laxIndent: blockParentIndent + 1,
      inlineFixedIndent:
          blockParentIndent + (_scanner.currentOffset - startOffset),
    );
  }

  /// Parses a block scalar.
  ///
  /// Block scalars can create in an implicit block map if declared on a new
  /// line. If [degenerateToImplicitMap] is `true`, then this function attempts
  /// to greedily parse a block map if possible.
  _BlockNode _parseBlockScalarWildcard(
    ScalarEvent event, {
    required int laxIndent,
    required int fixedIndent,
    required int indentLevel,
    required bool isInlined,
    required bool degenerateToImplicitMap,
  }) {
    final (
      PreScalar(
        :hasDocEndMarkers,
        :indentDidChange,
        :indentOnExit,
        :hasLineBreak,
      ),
      delegate,
    ) = _parseScalar(
      event,
      isImplicit: isInlined,
      isInFlowContext: false,
      indentLevel: indentLevel,
      minIndent: laxIndent, // Parse with minimum allowed indent
    );

    /// - Block keys cannot degenerate to implicit maps. Only flow keys.
    /// - We also need to make sure that the plain scalar didn't exit due to
    ///   an indent change.
    /// - Any scalar with a line break cannot be an implicit key
    if (!_scanner.canChunkMore ||
        !event.isFlowContext ||
        !degenerateToImplicitMap ||
        hasLineBreak ||
        indentDidChange) {
      return (
        delegate: delegate,
        nodeInfo: (
          exitIndent: indentOnExit,
          hasDocEndMarkers: hasDocEndMarkers,
        ),
      );
    }

    const kvColon = Indicator.mappingValue;
    var charAtCursor = _scanner.charAtCursor;

    if (event == ScalarEvent.startFlowDoubleQuoted ||
        event == ScalarEvent.startFlowSingleQuoted ||
        charAtCursor != kvColon) {
      final greedyIndent = _skipToParsableChar(_scanner, comments: _comments);

      // The indent must be null. This must be an inlined key.
      if (greedyIndent != null || !_scanner.canChunkMore) {
        return (
          delegate: delegate,
          nodeInfo: (
            exitIndent: greedyIndent,
            hasDocEndMarkers: false,
          ),
        );
      }

      charAtCursor = _scanner.charAtCursor;
    }

    // Always throw if this isn't a ":". It must be!
    if (charAtCursor != kvColon) {
      throw FormatException('Expected a ":" but found ${charAtCursor?.string}');
    }

    final map = MappingDelegate(
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,

      /// Map must now use the fixed indent we calculated. Forcing all keys to
      /// be aligned with the first key
      indent: fixedIndent,
      startOffset: delegate.startOffset, // Use offset of first key
      blockTags: {},
      inlineTags: {},
      blockAnchors: {},
      inlineAnchors: {},
    );

    return (delegate: map, nodeInfo: _parseBlockMap(map, delegate));
  }

  /// Parses a flow collection embedded within a block collection.
  ParserDelegate _parseEmbeddedFlowCollection(
    FlowCollectionEvent event, {
    required int indentLevel,
    required int indent,
    required bool isInlined,
    required bool isParsingKey,
    required bool isExplicitKey,
  }) => _parseFlowNode(
    /// Ensure we prevent an event check and default it to an event
    /// we are privy to thus limiting the scope of the function.
    /// Must parse a map/list. Throws otherwise, as expected.
    inferredEvent: event,

    /// Further reduces the scope of the function ensuring it throws
    /// when a "," is used at the beginning of the line. We want to ignore
    /// flow entry delimiters.
    isBlockContext: true,
    currentIndentLevel: indentLevel,
    minIndent: indent,

    isParsingKey: isParsingKey,
    isExplicitKey: isExplicitKey,
    forceInline: isInlined,
    keyIsJsonLike: false,

    /// Faux value. Never used. Block explicit keys are intercepted by the
    /// [_parseExplicitBlockEntry] function.
    collectionDelimiter: Indicator.reservedAtSign,
  );

  /// Parses a block node within a block collection.
  _BlockNode _parseBlockNode({
    required int indentLevel,
    required int laxIndent,
    required int fixedInlineIndent,
    required bool forceInlined,
    required bool isParsingKey,
    required bool isExplicitKey,
    required bool degenerateToImplicitMap,
    ParserEvent? event,
  }) {
    _BlockNodeInfo? info;
    ParserDelegate? node;

    switch (event ??
        _inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        )) {
      case FlowCollectionEvent flowEvent:
        {
          node = _parseEmbeddedFlowCollection(
            flowEvent,
            indentLevel: indentLevel,
            indent: laxIndent, // Indent doesn't matter that much
            isInlined: forceInlined,
            isParsingKey: isParsingKey,
            isExplicitKey: isExplicitKey,
          );

          info = (
            hasDocEndMarkers: false,
            exitIndent: _skipToParsableChar(_scanner, comments: _comments),
          );
        }

      case ScalarEvent scalarEvent:
        {
          final (:delegate, :nodeInfo) = _parseBlockScalarWildcard(
            scalarEvent,
            laxIndent: laxIndent,
            fixedIndent: fixedInlineIndent,
            indentLevel: indentLevel,
            isInlined: forceInlined,
            degenerateToImplicitMap: degenerateToImplicitMap,
          );

          info = nodeInfo;
          node = delegate;
        }

      case BlockCollectionEvent.startEntryValue:
        {
          final map = MappingDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            startOffset: _scanner.currentOffset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          node = map;
          info = _parseBlockMap(
            map,
            nullScalarDelegate(
              indentLevel: indentLevel,
              indent: fixedInlineIndent,
            ),
          );
        }

      case BlockCollectionEvent.startBlockListEntry when !forceInlined:
        {
          final list = SequenceDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            startOffset: _scanner.currentOffset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          node = list;
          info = _parseBlockSequence(list);
        }

      case BlockCollectionEvent.startExplicitKey when !forceInlined:
        {
          final map = MappingDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            startOffset: _scanner.currentOffset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          node = map;
          info = _parseBlockMap(map, null);
        }

      default:
        throw Exception("[Parser Error]: Should not be parsing node here");
    }

    /// Make sure we have an accurate indent and not one indicating that
    /// our block(-like) scalar was not a result of anything else like a
    /// comment.
    if (info.exitIndent == seamlessIndentMarker &&
        !info.hasDocEndMarkers &&
        _scanner.canChunkMore &&
        _scanner.charAtCursor == Indicator.comment) {
      info = (
        exitIndent: _skipToParsableChar(_scanner, comments: _comments),
        hasDocEndMarkers: false,
      );
    }

    return (delegate: node, nodeInfo: info);
  }

  /// Parses an explicit block map entry within a block collection declared
  /// using the `?` character.
  _BlockEntry _parseExplicitBlockEntry({
    required int indentLevel,
    required int indent,
  }) {
    final explicitChar = _scanner.charAtCursor;

    // Must have explicit key indicator
    if (explicitChar != Indicator.mappingKey) {
      throw Exception(
        'Expected an explicit key but found ${explicitChar?.string}',
      );
    }

    ({
      bool shouldExit,
      bool hasIndent,
      int? inferredIndent,
      int laxIndent,
      int inlineIndent,
    })
    checkIfParsable() {
      final startOffset = _scanner.currentOffset;

      _scanner.skipCharAtCursor(); // Skip the "?" or ":"

      /// Typically exists as "?"<whitespace>. We can't know what/where to
      /// start parsing. Skip to the next possible char
      final inferredIndent = _skipToParsableChar(_scanner, comments: _comments);

      // Must be able to parse more characters
      if (!_scanner.canChunkMore) {
        return (
          shouldExit: true,
          hasIndent: false,
          inferredIndent: seamlessIndentMarker,
          laxIndent: seamlessIndentMarker,
          inlineIndent: seamlessIndentMarker,
        );
      }

      final hasIndent = inferredIndent != null;

      if (hasIndent && inferredIndent < indent) {
        return (
          shouldExit: true,
          hasIndent: hasIndent,
          inferredIndent: inferredIndent,
          laxIndent: seamlessIndentMarker,
          inlineIndent: seamlessIndentMarker,
        );
      }

      final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
        inferredIndent,
        blockParentIndent: indent,
        startOffset: startOffset,
      );

      return (
        shouldExit: false,
        hasIndent: hasIndent,
        inferredIndent: inferredIndent,
        laxIndent: laxIndent,
        inlineIndent: inlineFixedIndent,
      );
    }

    // Check and see if we can parse the key first
    final (
      shouldExit: exitBeforeKey,
      hasIndent: keyHasIndent,
      inferredIndent: inferredKeyIndent,
      laxIndent: laxKeyIndent,
      inlineIndent: inlineKeyIndent,
    ) = checkIfParsable();

    if (exitBeforeKey) {
      return (
        nodeInfo: (exitIndent: inferredKeyIndent, hasDocEndMarkers: false),
        delegate: (
          key: nullScalarDelegate(indentLevel: indentLevel, indent: indent),
          value: null,
        ),
      );
    }

    ParserDelegate? explicitKey;

    final childIndentLevel = indentLevel + 1;

    /// Parse a key only if the indent is null or greater than the current
    /// indent. Since:
    ///   - Null indent indicates that the key is declared on the same line
    ///     with the indicator
    ///   - A larger indent indicates the element is more indented than the
    ///     indicator
    if (!keyHasIndent || inferredKeyIndent! > indent) {
      final (:nodeInfo, :delegate) = _parseBlockNode(
        indentLevel: childIndentLevel,
        laxIndent: laxKeyIndent,
        fixedInlineIndent: inlineKeyIndent,
        forceInlined: false,
        isParsingKey: true,
        isExplicitKey: true,
        degenerateToImplicitMap: true,
      );

      final (:exitIndent, :hasDocEndMarkers) = nodeInfo;

      final hasIndent = exitIndent != null;

      /// We can exit early if we are no longer at the current map's level
      /// based on the indent (the current map is the caller of this function)
      /// or the current document ended.
      if (hasDocEndMarkers || (hasIndent && exitIndent < indent)) {
        return (
          delegate: (
            key: delegate,
            value: null,
          ),
          nodeInfo: nodeInfo,
        );
      } else if ((!hasIndent &&
              _scanner
                  .canChunkMore) || // TODO: Revisit this condition. Explicit key must not declare value. Needs to be tested
          (hasIndent && exitIndent > indent)) {
        /// A ":" must be declared on a new line while being aligned with the
        /// "?" that triggered this key to be parsed. Thus, their indents
        /// *MUST* match.
        throw FormatException(
          'Expected ":" on a new line with an indent of $indent space(s) and'
          ' not ${exitIndent ?? 0} space(s)',
        );
      }

      explicitKey = delegate;
    }

    // We must have at least a key at this point. Even if null
    explicitKey ??= nullScalarDelegate(
      indentLevel: indentLevel,
      indent: indent,
    );

    /// At this point, we may be parsing a new node or the value of this
    /// explicit key since block nodes have no indicators. Ensure this is the
    /// case.
    if (_inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        ) !=
        BlockCollectionEvent.startEntryValue) {
      return (
        delegate: (
          key: explicitKey,
          value: null,
        ),
        nodeInfo: (
          exitIndent: indent,
          hasDocEndMarkers: false,
        ),
      );
    }

    // Skip ":" and check if we can parse it as a node
    final (
      :shouldExit,
      :hasIndent,
      :inferredIndent,
      :laxIndent,
      :inlineIndent,
    ) = checkIfParsable();

    /// No need to parse the value if we moved to the next line and the
    /// indent matches. Usually means there is no value to parse
    if (shouldExit || (hasIndent && inferredIndent! == indent)) {
      return (
        nodeInfo: (exitIndent: inferredIndent, hasDocEndMarkers: false),
        delegate: (
          key: explicitKey,
          value: null,
        ),
      );
    }

    final (:delegate, :nodeInfo) = _parseBlockNode(
      indentLevel: childIndentLevel,
      laxIndent: laxIndent,
      fixedInlineIndent: inlineIndent,
      forceInlined: false,
      isParsingKey: false,
      isExplicitKey: false,
      degenerateToImplicitMap: true,
    );

    return (delegate: (key: explicitKey, value: delegate), nodeInfo: nodeInfo);
  }

  /// Parses an implicit block map entry within a block collection.
  _BlockEntry _parseImplicitBlockEntry(
    ParserDelegate? key, {
    required int indent,
    required int indentLevel,
    ParserEvent? mapEvent,
  }) {
    ParserEvent nextEvent() => _inferNextEvent(
      _scanner,
      isBlockContext: true,
      lastKeyWasJsonLike: false,
    );

    var implicitKey = key;

    /// We should never see a block collection event for an explicit key/
    /// block list as implicit keys are restricted to a single line
    final event = mapEvent ?? nextEvent();

    if (event
        case BlockCollectionEvent.startBlockListEntry ||
            BlockCollectionEvent.startExplicitKey) {
      throw FormatException(
        'Implicit keys are restricted to a single line. Consider using an'
        ' explicit key for the entry',
      );
    }

    if (key == null && event != BlockCollectionEvent.startEntryValue) {
      final (:delegate, :nodeInfo) = _parseBlockNode(
        event: event,
        indentLevel: indentLevel,
        laxIndent: indent,
        fixedInlineIndent: indent,
        forceInlined: true,
        isParsingKey: true,
        isExplicitKey: false,
        degenerateToImplicitMap: false,
      );

      final (:hasDocEndMarkers, :exitIndent) = nodeInfo;

      /// The exit indent *MUST* be null or be seamless (parsed completely with
      /// no indent change if quoted). This is a key that should *NEVER*
      /// spill into the next line.
      if (exitIndent != null && exitIndent != seamlessIndentMarker) {
        throw Exception(
          '[Parser Error]: Implicit keys cannot have an exit indent',
        );
      }

      // This was never a key. We assumed it was a plain scalar and parsed it.
      if (hasDocEndMarkers) {
        return (nodeInfo: nodeInfo, delegate: (key: null, value: null));
      }

      implicitKey = delegate;
    }

    implicitKey ??= nullScalarDelegate(
      indentLevel: indentLevel,
      indent: indent,
    );

    // Must declare ":" on the same line
    if (_skipToParsableChar(_scanner, comments: _comments) != null ||
        nextEvent() != BlockCollectionEvent.startEntryValue) {
      throw FormatException(
        'Expected a ":" (after the key) but found '
        '${_scanner.charAtCursor?.string}',
      );
    }

    _scanner.skipCharAtCursor(); // Skip ":"

    final indentOrSeparation = _skipToParsableChar(
      _scanner,
      comments: _comments,
    );

    if (!_scanner.canChunkMore) {
      return (
        delegate: (key: implicitKey, value: null),
        nodeInfo: _emptyScanner,
      );
    }

    // We skipped separation space and the child is on the same line
    final isInlineChild = indentOrSeparation == null;
    final childEvent = nextEvent();

    final isBlockList = childEvent == BlockCollectionEvent.startBlockListEntry;

    /// YAML recommends grace for block lists that start on a new line but
    /// have the same indent as the implicit key since the "-" is usually
    /// perceived as indent.
    if (!isInlineChild &&
        (indentOrSeparation < indent ||
            (indentOrSeparation == indent && !isBlockList))) {
      return (
        delegate: (key: implicitKey, value: null),
        nodeInfo: (hasDocEndMarkers: false, exitIndent: indentOrSeparation),
      );
    } else if (isInlineChild && isBlockList) {
      throw FormatException('The block sequence must start on a new line');
    }

    final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
      indentOrSeparation,
      blockParentIndent: indent,
      startOffset: implicitKey.startOffset,
    );

    final (
      :delegate,
      nodeInfo: _BlockNodeInfo(:hasDocEndMarkers, :exitIndent),
    ) = _parseBlockNode(
      indentLevel: indentLevel + 1,
      laxIndent: indentOrSeparation ?? laxIndent,
      fixedInlineIndent: indentOrSeparation ?? inlineFixedIndent,
      forceInlined: false,
      isParsingKey: false,
      isExplicitKey: false,
      degenerateToImplicitMap: !isInlineChild, // Only if not inline
    );

    var indentOnExit = exitIndent;

    /// Implicit values exit immediately a line break is seen but do not skip
    /// it. However, the block parent (map) needs to have the correct indent
    /// info to prevent any premature termination before subsequent nodes can
    /// be parsed.
    if (_scanner.charAtCursor case LineBreak _ || WhiteSpace _
        when _scanner.canChunkMore &&
            !hasDocEndMarkers &&
            exitIndent == seamlessIndentMarker) {
      indentOnExit = _skipToParsableChar(_scanner, comments: _comments);
    }

    return (
      delegate: (key: implicitKey, value: delegate),
      nodeInfo: (exitIndent: indentOnExit, hasDocEndMarkers: hasDocEndMarkers),
    );
  }

  /// Throws if a block node is declared with an indent that is greater than
  /// the block parent's indent but less than the indent of the first child of
  /// the block
  void _throwIfDangling(int collectionIndent, int currentIndent) {
    if (_scanner.canChunkMore && currentIndent > collectionIndent) {
      throw FormatException(
        'Dangling node found at ${_scanner.charAtCursor?.string} with indent'
        '$currentIndent space(s) while parsing',
      );
    }
  }

  /// Parses a block map. If [firstImplicitKey] is present, the map parses
  /// only the value of the first key.
  _BlockNodeInfo _parseBlockMap(
    MappingDelegate map,
    ParserDelegate? firstImplicitKey,
  ) {
    var parsedKey = firstImplicitKey;
    final MappingDelegate(:indent, :indentLevel) = map;

    while (_scanner.canChunkMore) {
      ParserDelegate? key;
      ParserDelegate? value;
      _BlockNodeInfo mapInfo;

      // Implicit key already parsed
      if (parsedKey != null) {
        final (:delegate, :nodeInfo) = _parseImplicitBlockEntry(
          parsedKey,
          indent: indent,
          indentLevel: indentLevel,
        );

        mapInfo = nodeInfo;
        key = parsedKey;
        value = delegate.value;
      } else {
        final event = _inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        );

        final (
          :delegate,
          :nodeInfo,
        ) = event == BlockCollectionEvent.startExplicitKey
            ? _parseExplicitBlockEntry(indentLevel: indentLevel, indent: indent)
            : _parseImplicitBlockEntry(
                parsedKey,
                indent: indent,
                indentLevel: indentLevel,
                mapEvent: event,
              );

        mapInfo = nodeInfo;
        key = delegate.key;
        value = delegate.value;
      }

      final (:hasDocEndMarkers, :exitIndent) = mapInfo;

      /// Most probably encountered doc end chars while parsing implicit map.
      /// An explicit key should never return null here
      if (key == null) {
        return mapInfo;
      }

      if (!map.pushEntry(key, value)) {
        throw FormatException(
          'Block map cannot contain entries sharing the same key',
        );
      }

      if (hasDocEndMarkers) {
        return mapInfo;
      }

      /// If no doc end chars were found, indent on exit *MUST* not be null.
      /// Block collections rely only on indent as delimiters
      if (exitIndent == null) {
        if (_scanner.canChunkMore) {
          throw FormatException(
            'Invalid map entry found at ${_scanner.charAtCursor?.string} while'
            ' parsing block map',
          );
        }

        break;
      } else if (exitIndent < indent) {
        return mapInfo;
      }

      // Must not have a dangling indent at this point
      _throwIfDangling(indent, exitIndent);
      parsedKey = null;
    }

    return _emptyScanner;
  }

  /// Parses a block sequence.
  _BlockNodeInfo _parseBlockSequence(SequenceDelegate sequence) {
    const indicator = Indicator.blockSequenceEntry;
    final SequenceDelegate(:indent, :indentLevel) = sequence;

    bool exitOrThrowIfNotBlock() {
      final char = _scanner.charAtCursor;
      final charAfter = _scanner.peekCharAfterCursor();

      return switch (char) {
        /// Be gracious. Maybe we have doc end chars here.
        ///
        /// TODO: Remove zero indent for doc end chars? Mulling 🤔
        /// TODO: Should doc end chars hug left or just have any indent?
        indicator || Indicator.period
            when indent == 0 &&
                charAfter == char &&
                hasDocumentMarkers(_scanner, onMissing: (_) {}) =>
          true,

        // Normal "- " combination for block list
        indicator when charAfter is WhiteSpace || charAfter is LineBreak =>
          false,

        _ => throw FormatException(
          'Expected a "- " while parsing sequence but found '
          '${_scanner.charAtCursor?.string}',
        ),
      };
    }

    final childIndentLevel = indentLevel + 1;

    while (_scanner.canChunkMore) {
      if (exitOrThrowIfNotBlock()) {
        return (hasDocEndMarkers: true, exitIndent: null);
      }

      final startOffset = _scanner.currentOffset;

      _scanner.skipCharAtCursor(); // Skip "-"

      final indentOrSeparation = _skipToParsableChar(
        _scanner,
        comments: _comments,
      );

      if (!_scanner.canChunkMore) break;

      if (indentOrSeparation != null) {
        final isLess = indentOrSeparation < indent;

        // We moved to the next node irrespective of its indent.
        if (isLess || indentOrSeparation == indent) {
          sequence.pushEntry(
            nullScalarDelegate(
              indentLevel: childIndentLevel,
              indent: indent + 1,
            ),
          );

          if (isLess) {
            return (exitIndent: indentOrSeparation, hasDocEndMarkers: false);
          }

          continue;
        }
      }

      // Determine indentation
      final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
        indentOrSeparation,
        blockParentIndent: indent,
        startOffset: startOffset,
      );

      final (:delegate, :nodeInfo) = _parseBlockNode(
        indentLevel: childIndentLevel,
        laxIndent: laxIndent,
        fixedInlineIndent: inlineFixedIndent,
        forceInlined: false,
        isParsingKey: false,
        isExplicitKey: false,
        degenerateToImplicitMap: true,
      );

      sequence.pushEntry(delegate);

      final (:hasDocEndMarkers, :exitIndent) = nodeInfo;

      if (hasDocEndMarkers) return nodeInfo;

      /// If no doc end chars were never found, indent on exit *MUST* not be
      /// null. Block collections rely only on indent as delimiters
      if (exitIndent == null) {
        if (_scanner.canChunkMore) {
          throw FormatException(
            'Invalid block list entry found at'
            ' ${_scanner.charAtCursor?.string}. Expected ',
          );
        }

        break;
      } else if (exitIndent < indent) {
        return nodeInfo;
      }

      // Must no have a dangling indent at this point
      _throwIfDangling(indent, exitIndent);
    }

    return _emptyScanner;
  }
}
