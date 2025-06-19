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

    _scanner.skipCharAtCursor(); // Skip it if valid
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
      if (_scanner.charAtCursor case Indicator.flowEntryEnd) {
        _scanner.skipCharAtCursor();
        continue;
      }

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
      'or a terminating delimiter ${exitIndicator.string}',
    );

    if (!_nextLineSafeInFlow(minIndent, forceInline: forceInline)) {
      throw expectedCharErr;
    }

    bool ignoreValue(ReadableChar? char) {
      return char == null ||
          char == Indicator.flowEntryEnd ||
          char == exitIndicator;
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
            collectionDelimiter: exitIndicator,
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
    required Indicator collectionDelimiter,
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

    /// This is a failsafe. Every map/list (flow or block) must look for
    /// ways to ensure a `null` plain scalar is never returned. This ensures
    /// the internal parsing logic for parsing the map/list is correct. Each
    /// flow/block map/list handles missing values differently.
    ///
    /// TODO: Fix later
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

  ({int laxIndent, int inlineFixedIndent}) _blockChildIndent(
    int? inferred, {
    required int blockParentIndent,
    required int startOffset,
  }) {
    if (inferred != null) {
      return (laxIndent: inferred, inlineFixedIndent: inferred);
    }

    /// The calculation applies for both the "?" and ":" as the both have to
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
    ///     different upto the current parsable char. Forcing it to be aligned
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
    /// ? key: value
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

  _BlockNode _parseBlockScalarWildcard(
    ScalarEvent event, {
    required int laxIndent,
    required int fixedIndent,
    required int indentLevel,
    required bool isInlined,
    required bool degenerateToImplicitMap,
  }) {
    final (
      PreScalar(:hasDocEndMarkers, :indentOnExit, :hasLineBreak),
      delegate,
    ) = _parseScalar(
      event,
      isImplicit: isInlined,
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
        (indentOnExit != seamlessIndentMarker && indentOnExit < laxIndent)) {
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
    forceInline: false,
    keyIsJsonLike: false,

    /// Faux value. Never used. Block explicit keys are intercepted by the
    /// [_parseExplicitBlockEntry] function.
    collectionDelimiter: Indicator.reservedAtSign,
  );

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
            key:
                explicitKey ??
                nullScalarDelegate(
                  indentLevel: indentLevel,
                  indent: indent,
                ),
            value: null,
          ),
          nodeInfo: nodeInfo,
        );
      } else if ((!hasIndent && !_scanner.canChunkMore) ||
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

      /// The exit indent *MUST* be null. This is a key that should *NEVER*
      /// spill into the next line
      if (exitIndent != null) {
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

    void throwValueException() {
      throw FormatException(
        'Expected a ":" (after the key) but found '
        '${_scanner.charAtCursor?.string}',
      );
    }

    // Must declare ":" on the same line
    if (_skipToParsableChar(_scanner, comments: _comments) != null ||
        nextEvent() != BlockCollectionEvent.startEntryValue) {
      throwValueException();
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

    /// YAML recommends grace with block lists that start on a new line but
    /// have the same indent as the implicit key.
    if (!isInlineChild &&
        (indentOrSeparation < indent ||
            (indentOrSeparation == indent &&
                childEvent != BlockCollectionEvent.startBlockListEntry))) {
      return (
        delegate: (key: implicitKey, value: null),
        nodeInfo: (hasDocEndMarkers: false, exitIndent: indentOrSeparation),
      );
    }

    final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
      indentOrSeparation,
      blockParentIndent: indent,
      startOffset: implicitKey.startOffset,
    );

    final (:delegate, :nodeInfo) = _parseBlockNode(
      indentLevel: indentLevel + 1,
      laxIndent: indentOrSeparation ?? laxIndent,
      fixedInlineIndent: indentOrSeparation ?? inlineFixedIndent,
      forceInlined: isInlineChild,
      isParsingKey: false,
      isExplicitKey: false,
      degenerateToImplicitMap: !isInlineChild, // Only if not inline
    );

    return (delegate: (key: implicitKey, value: delegate), nodeInfo: nodeInfo);
  }

  void _throwIfDangling(int collectionIndent, int currentIndent) {
    if (currentIndent > collectionIndent) {
      throw FormatException(
        'Dangling node found at ${_scanner.charAtCursor?.string} with indent'
        '$currentIndent space(s) while parsing',
      );
    }
  }

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
        key = delegate.key;
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

      /// If no doc end chars were never found, indent on exit *MUST* not be
      /// null. Block collections rely only on indent as delimiters
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

      // Must no have a dangling indent at this point
      _throwIfDangling(indent, exitIndent);
      parsedKey = null;
    }

    return _emptyScanner;
  }

  _BlockNodeInfo _parseBlockSequence(SequenceDelegate sequence) {
    final SequenceDelegate(:indent, :indentLevel) = sequence;

    void throwIfNotIndicator() {
      if (_scanner.charAtCursor != Indicator.blockSequenceEntry) {
        throw FormatException(
          'Expected a "- " while parsing sequence but found '
          '${_scanner.charAtCursor?.string}',
        );
      }
    }

    final childIndentLevel = indentLevel + 1;

    while (_scanner.canChunkMore) {
      throwIfNotIndicator();

      final startOffset = _scanner.currentOffset;

      _scanner.skipCharAtCursor(); // Skip "-"

      final indentOrSeparation = _skipToParsableChar(
        _scanner,
        comments: _comments,
      );

      if (!_scanner.canChunkMore) break;

      if (indentOrSeparation != null && indentOrSeparation == indent) {
        sequence.pushEntry(
          nullScalarDelegate(indentLevel: indentLevel + 1, indent: indent + 1),
        );
        continue;
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
