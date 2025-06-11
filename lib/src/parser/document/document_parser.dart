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

  /// Delegate for the current node being parsed
  ParserDelegate? _currentDelegate;

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

  /// Tracks whether the documentation is using indentantion to convey
  /// content information.
  ///
  /// [NodeStyle.flow] has no use for indentation since it uses explicit
  /// indicators. Thus, parsing will be lenient with the document structure but
  /// will no allow nodes with [NodeStyle.block] to be used.
  bool _isBlockDoc = true;

  /// Tracks whether the parser should exit/prepare for an exit
  bool _exitNodeParser = false;

  final _greedyChars = <ReadableChar>[];

  final _anchorNodes = <String, ParserDelegate>{};

  final _parserEvents = <ParserEvent>[];

  SplayTreeSet<YamlComment> _comments = SplayTreeSet();

  bool _keyIsJsonLike(ParserDelegate? delegate) {
    if (delegate == null) return false;

    ParserDelegate unpack(ParserDelegate parser) {
      return switch (parser) {
        AliasDelegate a => a.anchorDelegate,
        _ => parser,
      };
    }

    final unpacked = switch (delegate) {
      MapEntryDelegate e => unpack(e.keyDelegate),
      _ => unpack(delegate),
    };

    if (unpacked case ScalarDelegate(
      preScalar: PreScalar(scalarStyle: ScalarStyle.doubleQuoted),
    )) {
      return true;
    }

    return false;
  }

  void _restartParser() {
    ++_currentIndex; // Move to next document

    if (_currentIndex == 0) return;

    _currentDelegate = null;

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
  }

  /// Parses directives and any its end marker if present
  _ParsedDocDirectives _processDirectives() {
    final (:yamlDirective, :globalTags, :reservedDirectives) = parseDirectives(
      _scanner,
    );

    var hasDocMarker = false;

    if (_scanner.charAtCursor
        case Indicator.blockSequenceEntry || Indicator.period) {
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

  YamlDocument? parseNext() {
    _restartParser();

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
          _currentDelegate?.parsed(),
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

    var (:foundDocEndMarkers, :isBlockDoc, :rootDelegate) = _parseNodeAtRoot(
      _scanner,
      rootInMarkerLine: _rootInMarkerLine,
      isDocStartExplicit: _docStartExplicit,
      hasDirectives: _hasDirectives,
      parserEvents: _parserEvents,
      comments: _comments,
    );

    _isBlockDoc = isBlockDoc;

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
          case null when _scanner.charAtCursor == Indicator.mappingValue:
            {
              isInlineScalar = false;
              final ScalarDelegate(:startOffset, :indent) = rootDelegate;

              _parserEvents
                ..add(
                  NodeEvent(
                    BlockCollectionEvent.startBlockMap,
                    MappingDelegate(
                      collectionStyle: NodeStyle.block,
                      indentLevel: 0,
                      indent: indent,
                      startOffset: startOffset,
                      blockTags: {},
                      inlineTags: {},
                      blockAnchors: {},
                      inlineAnchors: {},
                    ),
                  ),
                )
                ..add(
                  NodeEvent(
                    BlockCollectionEvent.startImplicitKey,
                    rootDelegate,
                  ),
                )
                ..add(BlockCollectionEvent.startEntryValue);
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

    while (_scanner.canChunkMore && !_exitNodeParser) {
      final event = _parserEvents.lastOrNull;

      if (event == null) {
        throw FormatException('A root event must always be present!');
      }

      // switch (event) {
      //   case ScalarEvent scalar:
      //     _parseScalar(scalar);

      //   case BlockCollectionEvent.startExplicitKey:
      //     _parseBlockKey(isExplicit: true);

      //   case BlockCollectionEvent.startImplicitKey:
      //     _parseBlockKey(isExplicit: false);
      // }
    }

    final root = _backtrackDelegate(_currentDelegate, matcher: (_) => false);

    assert(root != null, 'The root node should not be null here!!');

    return YamlDocument._(
      _currentIndex,
      version,
      tags.values.toSet(),
      reserved,
      _comments,
      root!.parsed(),
      YamlDocType.inferType(
        hasDirectives: _hasDirectives,
        isDocStartExplicit: _docStartExplicit,
      ),
      _docStartExplicit,
      _docEndExplicit,
    );
  }

  // void _parseExplicitBlockKey() {
  //   /// Track whitespace chars skipped as part of indent including the "?"
  //   /// indicator
  //   final charsSkipped = _scanner.skipWhitespace(skipTabs: true).length + 1;

  //   _scanner.skipCharAtCursor();

  //   switch (_scanner.charAtCursor) {
  //     // No more characters
  //     case null:
  //       _exitNodeParser = true;

  //     // Block value. A line break forces a value lookup
  //     case LineBreak _:
  //       _parserEvents.add(BlockCollectionEvent.startEntryValue);

  //     default:
  //       {
  //         final event = _inferNextEvent(
  //           _scanner,
  //           isBlockContext: true,
  //           lastKeyWasJsonLike: false,
  //         );

  //         // Ensure the flow collection is parsed inline
  //         if (event is FlowCollectionEvent) {
  //           _parserEvents.add(InlineFlowEvent(event));
  //           break;
  //         }

  //         final mapDelegate = _lookupNodeEvent(
  //             (e) => e.event == BlockCollectionEvent.startBlockMap,
  //           ).delegate;

  //         final inlineKeyIndent =

  //         // Block list chars are aligned
  //         if (event == BlockCollectionEvent.startBlockListEntry) {

  //           _parserEvents.add(
  //             NodeEvent(
  //               BlockCollectionEvent.startBlockList,
  //               SequenceDelegate(
  //                 collectionStyle: NodeStyle.block,
  //                 indentLevel: mapDelegate.indentLevel,
  //                 indent: mapDelegate.indent + charsSkipped,
  //                 startOffset: _scanner.currentOffset,
  //                 blockTags: {},
  //                 inlineTags: {},
  //                 blockAnchors: {},
  //                 inlineAnchors: {},
  //               ),
  //             ),
  //           );
  //         } else {
  //           /// An explicit key is just an implicit key whose value must start
  //           /// on new line
  //           _parserEvents.add(BlockCollectionEvent.startImplicitKey);
  //         }

  //         _parserEvents.add(event);
  //       }
  //   }
  // }

  /// Parses a flow continously.
  ///
  /// Explicit indicators, simple layout structure and disregard for
  /// indentation unless in within a block layout guarantee that we can block
  /// and pass flow indicators in one pass.
  void _parseFlowContinuous() {
    // Must ensure we are parsing a flow event always.
    final trigger = _parserEvents.lastOrNull;

    if (trigger == null || !trigger.isFlowContext) {
      throw FormatException(
        '[_parseFlowContinuous] function called on non-flow event',
      );
    }

    bool isDirtyFlowStart(ParserEvent event) {
      return event != FlowCollectionEvent.startFlowMap ||
          event != FlowCollectionEvent.startFlowSequence;
    }

    final dirtyException = FormatException(
      'Expected an opening "{" or "[" but found a dangling'
      ' "${_scanner.charAtCursor?.string}"',
    );

    void throwOnDirtyStart(ParserEvent event) {
      if (isDirtyFlowStart(event)) {
        throw dirtyException;
      }
    }

    var isParsingMap = false;
    var forceInline = false; // Parses in-line without any line break

    CollectionDelegate delegate;

    /// Determine the first possible event. This is a safeguard to ensure
    /// we always a valid [NodeEvent].
    switch (trigger) {
      case FlowCollectionEvent.nextFlowEntry:
        {
          // Wildcard action for either sequence or map
          _parserEvents.removeLast();

          /// We expect a flow node event immediately before. Usually
          /// indicates this is a top level map
          if (_parserEvents.lastOrNull case NodeEvent(
            event: final flowEvent,
            delegate: final nDelegate,
          ) when !isDirtyFlowStart(flowEvent)) {
            isParsingMap = flowEvent == FlowCollectionEvent.startFlowMap;
            delegate = nDelegate as CollectionDelegate;
            break;
          }

          throw dirtyException;
        }

      case BlockToFlowEvent(
        event: final parseEvent,
        indentLevel: final indentLevel,
        indent: final indent,
        isInline: final isInline,
      ):
        {
          // No inline event starts with flow entry or end flow delimiters
          throwOnDirtyStart(parseEvent);

          forceInline = isInline;

          const nodeStyle = NodeStyle.flow;
          final startOffset = _scanner.currentOffset;

          isParsingMap = parseEvent == FlowCollectionEvent.startFlowMap;
          delegate = parseEvent == FlowCollectionEvent.startFlowMap
              ? MappingDelegate(
                  collectionStyle: nodeStyle,
                  indentLevel: indentLevel,
                  indent: indent,
                  startOffset: startOffset,
                  blockTags: {},
                  inlineTags: {},
                  blockAnchors: {},
                  inlineAnchors: {},
                )
              : SequenceDelegate(
                  collectionStyle: nodeStyle,
                  indentLevel: indentLevel,
                  indent: indent,
                  startOffset: startOffset,
                  blockTags: {},
                  inlineTags: {},
                  blockAnchors: {},
                  inlineAnchors: {},
                );

          /// We will always have a starting sequence/map event. Create a node
          /// event and add it to the main event queue. Useful when
          /// backtracking
          _parserEvents.add(
            NodeEvent(
              parseEvent as FlowCollectionEvent,
              delegate,
            ),
          );
        }

      case NodeEvent(event: final parserEvent)
          when isDirtyFlowStart(parserEvent):
        throw dirtyException;

      default:
        throw dirtyException;
    }

    isParsingMap
        ? _parseFlowMap(
            delegate as MappingDelegate,
            forceInline: forceInline,
          )
        : _parseFlowSequence(
            delegate as SequenceDelegate,
            forceInline: forceInline,
          );
  }

  void _throwNonInline({required bool isBlock}) => throw FormatException(
    'Found a line break when parsing a ${isBlock ? 'block' : 'flow'} node '
    'just before ${_scanner.currentOffset}',
  );

  bool _nextLineSafeInFlow(int minIndent, {required bool forceInline}) {
    final indent = _skipToParsableChar(_scanner, comments: _comments);

    if (indent != null) {
      // Must not have line breaks
      if (forceInline) _throwNonInline(isBlock: false);

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

  void _throwIfNotFlowDelimiter(Indicator delimiter) {
    _skipToParsableChar(_scanner, comments: _comments);

    final char = _scanner.charAtCursor;

    if (char != delimiter) {
      throw FormatException(
        'Expected the closing flow delimiter: ${delimiter.string} but found: '
        '${char?.string ?? ''} at ${_scanner.charAtCursor}',
      );
    }
  }

  void _parseFlowMap(MappingDelegate delegate, {required bool forceInline}) {
    final MappingDelegate(:indent, :indentLevel) = delegate;
    const mapEnd = Indicator.mappingEnd;

    _scanner.skipCharAtCursor(); // Skip opening delimiter

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
      if (_scanner.charAtCursor case Indicator.flowEntryEnd) continue;

      break; // Always assume we are ending the parsing if not continuing!
    }

    _throwIfNotFlowDelimiter(mapEnd);
  }

  void _parseFlowSequence(
    SequenceDelegate delegate, {
    required bool forceInline,
  }) {
    final SequenceDelegate(:indent, :indentLevel) = delegate;
    const seqEnd = Indicator.flowSequenceEnd;

    _scanner.skipCharAtCursor(); // Skip leading "["

    listParser:
    while (_scanner.canChunkMore) {
      // Always ensure we are at a parsable char. Safely.
        if (!_nextLineSafeInFlow(indent, forceInline: forceInline)) break;

      final charAfter = _scanner.peekCharAfterCursor();

      // Fast track an exit
      if (charAfter == null) {
        _scanner.skipCharAtCursor();
        break;
      }

      // We will always have a char here
      switch (_scanner.charAtCursor) {
        case Indicator.flowEntryEnd:
          {
            final exception = delegate.isEmpty
                ? FormatException(
                    'Expected to find the first value but found ","',
                  )
                : FormatException(
                    'Found a duplicate "," before finding a'
                    ' flow sequence entry',
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
    );

    final keyIsJsonLike = _keyIsJsonLike(parsedKey);

    final expectedCharErr = FormatException(
      'Expected a next flow entry indicator "," or a map value indicator ":" '
      'or a terminating delimiter ${exitIndicator.string}',
    );

    if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline)) {
      throw expectedCharErr;
    }

    bool ignoreValue(ReadableChar? char) {
      return char == Indicator.flowEntryEnd || char == exitIndicator;
    }

    switch (_scanner.charAtCursor) {
      case Indicator.mappingValue
          when keyIsJsonLike ||
              _scanner.peekCharAfterCursor() == WhiteSpace.space:
        {
          _scanner.skipCharAtCursor();

          if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline)) {
            throw expectedCharErr;
          }

          if (ignoreValue(_scanner.charAtCursor)) break;

          value = _parseFlowNode(
            isParsingKey: false,
            currentIndentLevel: indentLevel + 1, // One level deeper than key
            minIndent: minIndent,
            forceInline: forceInline,
            isExplicitKey: false,
            keyIsJsonLike: keyIsJsonLike,
          );
        }

      case ReadableChar char when ignoreValue(char):
        break;

      default:
        throw expectedCharErr;
    }

    return (parsedKey, value);
  }

  ParserDelegate _parseFlowNode({
    required bool isParsingKey,
    required int currentIndentLevel,
    required int minIndent,
    required bool forceInline,
    required bool isExplicitKey,
    required bool keyIsJsonLike,
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
          if (!_nextLineSafeInFlow(
            minIndent,
            forceInline: forceInline,
          )) {
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

            /// A plain scalar is always restricted to a single line unless it
            /// is an explicit key. Last failsafe condition.
            isImplicit:
                forceInline ||
                isImplicitKey ||
                (!isExplicitKey && event == ScalarEvent.startFlowPlain),
            indentLevel: currentIndentLevel,
            minIndent: minIndent,
          );

          /// Plain scalars can have document/directive end chars embedded
          /// in the content. If not implicit, it can be affected by indent
          /// changes since it has a block-like structure
          if (prescalar case PreScalar(
            scalarStyle: ScalarStyle.plain,
            indent: final parsedIndent,
            indentDidChange: final changedIndent,
            hasDocEndMarkers: final docDidEnd,
          )) {
            // Flow node only ends after parsing a flow delimiter
            if (docDidEnd) {
              throw FormatException(
                "Premature document termination when parsing flow map entry.",
              );
            }

            // Must not detect an indent change less than flow indent
            if (changedIndent && parsedIndent < minIndent) {
              throw FormatException(
                'Indent change detected when parsing plain scalar. Expected'
                ' $minIndent spaced but found $parsedIndent spaces',
              );
            }
          }

          return delegate;
        }

      case FlowCollectionEvent.nextFlowEntry
          when !isParsingKey || isExplicitKey:
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

  (PreScalar scalar, ScalarDelegate delegate) _parseScalar(
    ScalarEvent event, {
    required bool isImplicit,
    required int indentLevel,
    required int minIndent,
  }) {
    final startOffset = _scanner.currentOffset;

    final prescalar = switch (event) {
      ScalarEvent.startBlockLiteral || ScalarEvent.startBlockFolded
          when !isImplicit =>
        parseBlockStyle(_scanner, minimumIndent: minIndent),

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
      )!,

      _ => throw FormatException(
        'Failed to parse block scalar as it can never be implicit!',
      ),
    };

    return (
      prescalar,
      ScalarDelegate(
        indentLevel: indentLevel,
        indent: prescalar.indent,
        startOffset: startOffset,
        blockTags: {},
        inlineTags: {},
        blockAnchors: {},
        inlineAnchors: {},
      )..scalar = prescalar,
    );
  }
}
