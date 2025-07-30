part of 'yaml_document.dart';

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

  final _anchorNodes = <String, ParsedYamlNode>{};

  SplayTreeSet<YamlComment> _comments = SplayTreeSet();

  ParserDelegate _trackAnchor(
    ParserDelegate delegate,
    NodeProperties? properties,
  ) {
    if (properties case NodeProperties(:final String anchor)) {
      _anchorNodes[anchor] = delegate.parsed();
    }

    return delegate..updateNodeProperties = properties;
  }

  AliasDelegate _referenceAlias(
    NodeProperties properties, {
    required int indentLevel,
    required int indent,
    required SourceLocation start,
  }) {
    final alias = properties.alias;

    if (_anchorNodes[alias] case ParsedYamlNode node) {
      return AliasDelegate(
        node,
        indentLevel: indentLevel,
        indent: indent,
        start: start,
      );
    }

    throw FormatException('Node alias "$alias" is unrecognized');
  }

  ParserDelegate? _nullOrAlias(
    NodeProperties? properties, {
    required int indentLevel,
    required int indent,
    required SourceLocation start,
  }) {
    if (properties == null) return null;

    final node = (properties.isAlias
        ? _referenceAlias(
            properties,
            indentLevel: indentLevel,
            indent: indent,
            start: start,
          )
        : properties.parsedAnchorOrTag
        ? nullScalarDelegate(
            indentLevel: indentLevel,
            indent: indent,
            startOffset: start,
          )
        : null);

    return node != null ? _trackAnchor(node, properties) : node;
  }

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

  /// Resolves a local tag to a global tag uri if present.
  ResolvedTag _resolveTag(LocalTag localTag) {
    final LocalTag(:tagHandle, :content) = localTag;

    SpecificTag tag = localTag;
    var suffix = ''; // Local tags have no suffixes

    // Check if alias to global tag
    final globalTag = _globalTags[tagHandle];
    final hasGlobalTag = globalTag != null;

    switch (tagHandle.handleVariant) {
      // All named tags must have a corresponding global tag
      case TagHandleVariant.named:
        {
          if (!hasGlobalTag) {
            throw FormatException(
              'Named tag "$localTag" has no corresponding global tag',
            );
          } else if (content.isEmpty) {
            throw FormatException('Named tag "$localTag" has no suffix');
          }

          continue resolver;
        }

      // Secondary tags limited to tags only supported by YAML
      case TagHandleVariant.secondary when !yamlTags.contains(localTag):
        throw FormatException(
          'Unrecognized secondary tag "$localTag". Expected any of: $yamlTags',
        );

      resolver:
      default:
        {
          if (hasGlobalTag) {
            tag = globalTag;
            suffix = content; // Local tag is prefixed with global tag uri
          }
        }
    }

    return ParsedTag(tag, suffix);
  }

  /// Parses a [Scalar].
  (PreScalar scalar, ScalarDelegate delegate) _parseScalar(
    ScalarEvent event, {
    required bool isImplicit,
    required bool isInFlowContext,
    required int indentLevel,
    required int minIndent,
    SourceLocation? start,
  }) {
    final scalarOffset = start ?? _scanner.lineInfo().current;

    final prescalar = switch (event) {
      ScalarEvent.startBlockLiteral || ScalarEvent.startBlockFolded
          when !isImplicit && !isInFlowContext =>
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
        start: scalarOffset,
      )..scalar = prescalar,
    );
  }

  _MapPreflightInfo _checkMapState(
    _ParsedNodeProperties? parsedProperties, {
    required bool isBlockContext,
    required int minMapIndent,
  }) {
    final skippedOrParsedAny = parsedProperties != null;
    final event = _inferNextEvent(
      _scanner,
      isBlockContext: isBlockContext,
      lastKeyWasJsonLike: false,
    );

    bool ensureMapIsSafe(int? indentOnExit) {
      if (indentOnExit != null) {
        if (isBlockContext) {
          _throwIfDangling(minMapIndent, indentOnExit, allowProperties: false);
          return indentOnExit == minMapIndent;
        } else {
          if (indentOnExit < minMapIndent) {
            throw FormatException(
              'Expected at ${minMapIndent - indentOnExit} additional spaces but'
              ' found: ${_scanner.charAtCursor}',
            );
          }
        }
      }

      return true;
    }

    if (event
        case BlockCollectionEvent.startExplicitKey ||
            FlowCollectionEvent.startExplicitKey) {
      var blockMapContinue = true;
      int? exitIndent;

      /// Explicit keys cannot have properties. Do not be confused by this
      /// condition. Most parsing functions use the [_parseNodeProperties]
      /// functions to also skip to the next parsable char
      if (skippedOrParsedAny) {
        final _ParsedNodeProperties(:indentOnExit, :parsedAny) =
            parsedProperties;

        if (parsedAny) {
          throw FormatException(
            'Explicit keys cannot have any node properties before the "?" '
            'indicator',
          );
        }

        blockMapContinue = ensureMapIsSafe(indentOnExit);
        exitIndent = indentOnExit;
      }

      return (
        event: event,
        hasProperties: false,
        blockMapContinue: blockMapContinue,
        isExplicitEntry: true,
        indentOnExit: exitIndent,
      );
    }

    // Implicit keys cannot span multiple lines
    if (skippedOrParsedAny) {
      final _ParsedNodeProperties(:isMultiline, :indentOnExit, :parsedAny) =
          parsedProperties;

      if (parsedAny && isMultiline) {
        throw FormatException(
          'Node properties for an implicit ${isBlockContext ? 'block' : 'flow'}'
          ' key cannot span multiple lines',
        );
      }

      return (
        event: event,
        hasProperties: true,
        isExplicitEntry: false,
        blockMapContinue: ensureMapIsSafe(indentOnExit),
        indentOnExit: indentOnExit,
      );
    }

    return (
      event: event,
      hasProperties: false,
      isExplicitEntry: false,
      blockMapContinue: true,
      indentOnExit: null,
    );
  }

  ParserDelegate? _aliasKeyOrNull(
    NodeProperties? properties, {
    ParserDelegate? existing,
    required int indentLevel,
    required int indent,
    required SourceLocation keyStartOffset,
  }) {
    if (properties case NodeProperties(:final isAlias) when isAlias) {
      if (existing != null) {
        throw FormatException(
          'An existing key found while attempting to reference an alias',
        );
      }

      return _referenceAlias(
        properties,
        indentLevel: indentLevel,
        indent: indent,
        start: keyStartOffset,
      );
    }

    return null;
  }

  /// Skips to the next parsable flow indicator/character.
  ///
  /// If declared on a new line and [forceInline] is `false`, the flow
  /// indicator/character must be indented at least [minIndent] spaces. Throws
  /// otherwise.
  bool _nextSafeLineInFlow(int minIndent, {required bool forceInline}) {
    final indent = _skipToParsableChar(_scanner, comments: _comments);

    if (indent != null) {
      // Must not have line breaks
      if (forceInline) {
        throw FormatException(
          'Found a line break when parsing a flow node just before '
          '${_scanner.lineInfo().current}',
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

  bool _continueToNextEntry(
    int minIndent, {
    required bool forceInline,
  }) {
    _nextSafeLineInFlow(minIndent, forceInline: forceInline);

    if (_scanner.charAtCursor case Indicator.flowEntryEnd) {
      _scanner.skipCharAtCursor();
      _nextSafeLineInFlow(minIndent, forceInline: forceInline);
      return true;
    }

    return false;
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

  /// Parses a single flow map entry.
  (ParserDelegate? key, ParserDelegate? value) _parseFlowMapEntry(
    ParserDelegate? key, {
    required int indentLevel,
    required int minIndent,
    required bool forceInline,
    required Indicator exitIndicator,
    SourceLocation? startOffset,
  }) {
    var parsedKey = key;
    ParserDelegate? value;

    if (!_nextSafeLineInFlow(minIndent, forceInline: forceInline) ||
        _scanner.charAtCursor == exitIndicator) {
      return (key, value);
    }

    /// You may notice an intentional syntax change to how nodes are being
    /// parsed, that is, limited use of [ParserEvent]. This is because the
    /// scope is limited when actual parsing is being done. We don't need
    /// events here to know what fine grained action we need to do.
    if (_scanner.charAtCursor case Indicator.flowEntryEnd when key == null) {
      throw FormatException(
        'Expected at least a key in the flow map entry but found ","',
      );
    }

    parsedKey ??= _parseFlowNode(
      isParsingKey: true,
      startOffset: startOffset,
      currentIndentLevel: indentLevel,
      minIndent: minIndent,
      forceInline: forceInline,

      /// Defaults to false. The function will recursively infer internally
      /// if `true` and act accordingly
      isExplicitKey: false,
      keyIsJsonLike: false,
      collectionDelimiter: exitIndicator,
    );

    final expectedCharErr = FormatException(
      'Expected a next flow entry indicator "," or a map value indicator ":" '
      'or a terminating delimiter "${exitIndicator.string}"',
    );

    if (!_nextSafeLineInFlow(minIndent, forceInline: forceInline)) {
      throw expectedCharErr;
    }

    /// Checks if we should parse a value or ignore it
    bool ignoreValue(ReadableChar? char) {
      return char == null ||
          char == Indicator.flowEntryEnd ||
          char == exitIndicator;
    }

    final valueOffset = _scanner.lineInfo().current;
    parsedKey.updateEndOffset = valueOffset;

    // Check if this is the start of a flow value
    if (_inferNextEvent(
          _scanner,
          isBlockContext: false,
          lastKeyWasJsonLike: _keyIsJsonLike(parsedKey),
        ) ==
        FlowCollectionEvent.startEntryValue) {
      _scanner.skipCharAtCursor(); // ":"

      final _FlowNodeProperties(:event, :properties) = _parseSimpleFlowProps(
        _scanner,
        minIndent: minIndent,
        resolver: _resolveTag,
        comments: _comments,
        lastKeyWasJsonLike: false, // no effect
      );

      final valueLevel = indentLevel + 1;

      /// Having a ":" changes the layout dynamics. This means the value is
      /// present-ish by virtue of having seen the delimiter. This ensures
      /// we provide the correct end offset for an editor trying to make
      /// edits to the source. Such that:
      ///
      ///
      /// {
      /// key,
      ///    ^ Key ends here by default. Value null, non-existent (virtual)
      ///
      /// key:,
      ///    ^^ Key ends at the first caret. Value is null, but exists since
      ///       the ":" is present. Thus a "physical" null that ends at the
      ///       second caret.
      /// }
      if (properties?.isAlias ?? false) {
        value =
            _referenceAlias(
                properties!,
                indentLevel: valueLevel,
                indent: minIndent,
                start: valueOffset,
              )
              ..updateNodeProperties = properties
              ..updateEndOffset = _scanner.lineInfo().current;
      } else {
        value = _trackAnchor(
          ignoreValue(_scanner.charAtCursor)
              ? (nullScalarDelegate(
                  indentLevel: valueLevel,
                  indent: minIndent,
                  startOffset: valueOffset,
                )..updateEndOffset = _scanner.lineInfo().current)
              : _parseFlowNode(
                  inferredEvent: event,
                  isParsingKey: false,
                  currentIndentLevel: valueLevel,
                  minIndent: minIndent,
                  forceInline: forceInline,
                  isExplicitKey: false,
                  keyIsJsonLike: false, // No effect here
                  collectionDelimiter: exitIndicator,
                ),
          properties,
        );
      }
    } else if (!ignoreValue(_scanner.charAtCursor)) {
      // Must at least be end of parser, "," and ["}" if map or "]" if list]
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
    SourceLocation? startOffset,
  }) {
    final event =
        inferredEvent ??
        _inferNextEvent(
          _scanner,
          isBlockContext: false,
          lastKeyWasJsonLike: keyIsJsonLike,
        );

    final flowStartOffset = startOffset ?? _scanner.lineInfo().current;

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
          startOffset: flowStartOffset,
        )..updateEndOffset = flowStartOffset;

      case FlowCollectionEvent.startExplicitKey:
        {
          _scanner.skipCharAtCursor();

          if (!_nextSafeLineInFlow(
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
              startOffset: flowStartOffset,
            )..updateEndOffset = _scanner.lineInfo().current;
          }

          return _parseFlowNode(
            isParsingKey: isParsingKey,
            currentIndentLevel: currentIndentLevel,
            minIndent: minIndent,
            forceInline: forceInline,
            isExplicitKey: true,
            keyIsJsonLike: keyIsJsonLike,
            collectionDelimiter: collectionDelimiter,
            startOffset: flowStartOffset,
          );
        }

      case FlowCollectionEvent.startFlowMap:
        {
          final map = MappingDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: currentIndentLevel + 1,
            indent: minIndent,
            start: flowStartOffset,
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
            start: flowStartOffset,
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
            start: flowStartOffset,
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
            startOffset: flowStartOffset,
          )..updateEndOffset = flowStartOffset;
        }

      default:
        throw FormatException(
          '[Parser Error]: Should not be parsing flow node here',
        );
    }
  }

  /// Parses a flow map.
  ///
  /// If [forceInline] is `true`, the map must be declared on the same line
  /// with no line breaks and throws if otherwise.
  void _parseFlowMap(MappingDelegate delegate, {required bool forceInline}) {
    _throwIfNotFlowDelimiter(Indicator.mappingStart);

    final MappingDelegate(:indent, :indentLevel) = delegate;
    const mapEnd = Indicator.mappingEnd;

    /// We need to ensure we don't unintentionally make the first key's
    /// property's multiline if implicit and declared inline. This may happen
    /// if the first key is not declared on the same line as the "{".
    _nextSafeLineInFlow(indent, forceInline: forceInline);

    while (_scanner.canChunkMore) {
      final keyOffset = _scanner.lineInfo().current;

      final props = _parseNodeProperties(
        _scanner,
        minIndent: indent,
        resolver: _resolveTag,
        comments: _comments,
      );

      _checkMapState(props, isBlockContext: false, minMapIndent: indent);

      final keyProps = props.properties;

      final (key, value) = _parseFlowMapEntry(
        _aliasKeyOrNull(
          keyProps,
          indentLevel: indentLevel,
          indent: indent,
          keyStartOffset: keyOffset,
        ),
        startOffset: keyOffset,
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

      _trackAnchor(key, keyProps);

      // Map already contains key
      if (!delegate.pushEntry(key, value)) {
        // TODO: Show next key to help user know which key!
        // TODO: Inline the key if too long
        throw FormatException(
          'Flow map cannot contain duplicate entries by the same key',
        );
      }

      // Only continues if current non-space character is a ","
      if (!_continueToNextEntry(indent, forceInline: forceInline)) {
        break;
      }
    }

    _throwIfNotFlowDelimiter(mapEnd);
    delegate.updateEndOffset = _scanner.lineInfo().current;
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

    /// Similar to flow map, move this to the first parsable char. This has
    /// little effect for other sequence entries but may be crucial to
    /// compact maps (flow map entries without leading "{" and trailing "}")
    /// that may suffer from the same issue we want to suppress in a flow
    /// map's first key.
    _nextSafeLineInFlow(indent, forceInline: forceInline);

    listParser:
    while (_scanner.canChunkMore) {
      final flowStartOffset = _scanner.lineInfo().current;

      final (:event, :properties, :hasMultilineProps) = _parseSimpleFlowProps(
        _scanner,
        minIndent: indent,
        resolver: _resolveTag,
        comments: _comments,
      );

      // We will always have a char here
      switch (event) {
        case FlowCollectionEvent.nextFlowEntry:
          {
            if (_nullOrAlias(
                  properties,
                  indentLevel: indentLevel,
                  indent: indent,
                  start: flowStartOffset,
                )
                case ParserDelegate entry) {
              delegate.pushEntry(entry); // TODO: Test this
              break;
            }

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
        case FlowCollectionEvent.startExplicitKey:
          {
            if (properties != null) {
              throw FormatException(
                'Explicit keys cannot have any node properties before the "?" '
                'indicator',
              );
            }

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
                ..updateValue = value,
            );
          }

        case FlowCollectionEvent.endFlowSequence:
          break listParser;

        default:
          {
            ParserDelegate? keyOrElement;

            if (properties != null && properties.isAlias) {
              keyOrElement = _referenceAlias(
                properties,
                indentLevel: indentLevel,
                indent: indent,
                start: flowStartOffset,
              );
            }

            // Handles all flow node types i.e map, sequence and scalars
            keyOrElement ??= _parseFlowNode(
              isParsingKey: false,
              currentIndentLevel: indentLevel,
              minIndent: indent,
              forceInline: forceInline,
              isExplicitKey: false,
              keyIsJsonLike: false,
              startOffset: flowStartOffset,
              collectionDelimiter: seqEnd,
            );

            // Go to the next parsable char
            if (!_nextSafeLineInFlow(indent, forceInline: forceInline)) {
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
              delegate.pushEntry(_trackAnchor(keyOrElement, properties));
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

            final entry = MapEntryDelegate(
              nodeStyle: NodeStyle.flow,
              keyDelegate: keyOrElement,
            )..updateValue = value;

            _trackAnchor(hasMultilineProps ? entry : keyOrElement, properties);
            delegate.pushEntry(entry);
          }
      }

      if (!_continueToNextEntry(indent, forceInline: forceInline)) {
        break;
      }
    }

    _throwIfNotFlowDelimiter(seqEnd);
    delegate.updateEndOffset = _scanner.lineInfo().current;
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

    /// Being null indicates the child is okay being indented at least "+1" if
    /// the rest of its content spans multiple lines. This applies to
    /// [ScalarStyle.literal] and [ScalarStyle.folded]. Flow collections also
    /// benefit from this as the indent serves no purpose other than respecting
    /// the current block parent's indentation. This is its [laxIndent].
    ///
    /// Its [inlineFixedIndent] is the character difference upto the current
    /// parsable char. This indent is enforced on block sequences and maps used
    /// as:
    ///   1. a block sequence entry
    ///   2. content of an explicit key
    ///   3. content of an explicit key's value
    ///
    /// "?" is used as an example but applies to all block nodes that use an
    /// indicator.
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
    ///   keyB: value
    ///   keyC: value # Explicit key ends here
    /// : actual-value # Explicit key's value
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
          blockParentIndent +
          (_scanner.lineInfo().current.offset - startOffset),
    );
  }

  /// Parses a block scalar.
  ///
  /// Block scalars can create in an implicit block map if declared on a new
  /// line. If [degenerateToImplicitMap] is `true`, then this function attempts
  /// to greedily parse a block map if possible.
  ///
  ///
  _BlockNode _parseBlockScalarWildcard(
    ScalarEvent event, {
    required SourceLocation startOffset,
    required int laxIndent,
    required int fixedIndent,
    required int indentLevel,
    required bool isInlined,
    required bool degenerateToImplicitMap,
    required bool parentEnforcedCompactness,
    required _ParsedNodeProperties? parsedProperties,
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
      start: startOffset,
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
        delegate: _trackAnchor(delegate, parsedProperties?.properties),
        nodeInfo: (
          exitIndent: indentOnExit,
          hasDocEndMarkers: hasDocEndMarkers,
        ),
      );
    }

    var charAtCursor = _scanner.charAtCursor;

    if (event == ScalarEvent.startFlowDoubleQuoted ||
        event == ScalarEvent.startFlowSingleQuoted ||
        charAtCursor != Indicator.mappingValue) {
      final greedyIndent = _skipToParsableChar(_scanner, comments: _comments);

      // The indent must be null. This must be an inlined key.
      if (greedyIndent != null || !_scanner.canChunkMore) {
        return (
          delegate: _trackAnchor(delegate, parsedProperties?.properties),
          nodeInfo: (
            exitIndent: greedyIndent,
            hasDocEndMarkers: false,
          ),
        );
      }

      charAtCursor = _scanner.charAtCursor;
    }

    // Always throw if this isn't a ":". It must be!
    if (_inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        ) !=
        BlockCollectionEvent.startEntryValue) {
      throw FormatException(
        'Expected a ": " but found ${charAtCursor?.string}',
      );
    }

    final map = MappingDelegate(
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,

      /// Map must now use the fixed indent we calculated. Forcing all keys to
      /// be aligned with the first key
      indent: fixedIndent,
      start: delegate.start, // Use offset of first key
    );

    if (parsedProperties != null) {
      final _ParsedNodeProperties(:isMultiline, :parsedAny, :properties) =
          parsedProperties;

      // Compact nodes cannot have node properties
      if (parentEnforcedCompactness && parsedAny) {
        throw FormatException(
          'Compact implicit block maps cannot have node properties',
        );
      }

      _trackAnchor(isMultiline ? map : delegate, properties);
    }

    return (delegate: map, nodeInfo: _parseBlockMap(map, delegate, null));
  }

  /// Parses a flow collection embedded within a block collection.
  ParserDelegate _parseEmbeddedFlowCollection(
    FlowCollectionEvent event, {
    required int indentLevel,
    required int indent,
    required bool isInlined,
    required bool isParsingKey,
    required bool isExplicitKey,
    required SourceLocation startOffset,
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
    startOffset: startOffset,
  );

  void _throwIfNotCompactCompatible(
    _ParsedNodeProperties? parsedProperties, {
    required bool parentEnforcedCompactness,
    required bool isBlockSequence,
  }) {
    if (parsedProperties case _ParsedNodeProperties(
      :final isMultiline,
      :final parsedAny,
    ) when parsedAny) {
      // Compact notation prevents nodes from having properties
      if (parentEnforcedCompactness) {
        throw FormatException(
          'A compact block node cannot have node properties',
        );
      } else if (!isMultiline) {
        throw FormatException(
          'Inline node properties cannot be declared before the first '
          '${isBlockSequence ? '"- "' : '"? "'} indicator',
        );
      }
    }
  }

  /// Parses a block node within a block collection.
  _BlockNode _parseBlockNode({
    required int indentLevel,
    required int laxIndent,
    required int fixedInlineIndent,
    required bool forceInlined,
    required bool isParsingKey,
    required bool isExplicitKey,
    required bool degenerateToImplicitMap,
    required bool parentEnforcedCompactness,
    required SourceLocation startOffset,
    required _ParsedNodeProperties? parsedProperties,
    ParserEvent? event,
  }) {
    _BlockNodeInfo? info;
    ParserDelegate? node;

    final parsedProps = parsedProperties != null;

    if (parsedProps && parsedProperties.properties.isAlias) {
      final props = parsedProperties.properties;

      // Lax indent is always the minimum
      return (
        delegate: _referenceAlias(
          props,
          indentLevel: indentLevel,
          indent: laxIndent,
          start: startOffset,
        )..updateNodeProperties = props,
        nodeInfo: (exitIndent: laxIndent, hasDocEndMarkers: false),
      );
    }

    switch (event ??
        _inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        )) {
      case FlowCollectionEvent flowEvent:
        {
          node = _trackAnchor(
            _parseEmbeddedFlowCollection(
              flowEvent,
              indentLevel: indentLevel,
              indent: laxIndent, // Indent doesn't matter that much
              isInlined: forceInlined,
              isParsingKey: isParsingKey,
              isExplicitKey: isExplicitKey,
              startOffset: startOffset,
            ),
            parsedProperties?.properties,
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
            parentEnforcedCompactness: parentEnforcedCompactness,
            startOffset: startOffset,
            parsedProperties: parsedProperties,
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
            start: startOffset,
          );

          ParserDelegate? nonExistentKey = nullScalarDelegate(
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            startOffset: startOffset,
          )..updateEndOffset = _scanner.lineInfo().current;

          _ParsedNodeProperties? downStream;
          NodeProperties? mapProps;

          /// We want to allow the map to determine its own state. Ideally,
          /// this could be achieved here but a map can have multiple values?
          ///
          /// We want to reduce wasted cycles doing the same check. Because..
          /// <insert Spongebob meme> "A bLoCk MaP aLwAyS dEtErMiNeS iT's StAtE"
          /// before parsing a block entry and each (implicit/explicit) block
          /// entry is handled differently.
          ///
          /// If there are no node properties. We can safely just pass a null
          /// key and wrapped in a delegate
          if (parsedProps && parsedProperties.parsedAny) {
            final _ParsedNodeProperties(:isMultiline, :properties) =
                parsedProperties;

            if (isMultiline) {
              mapProps = properties;
              downStream = null;
            } else {
              nonExistentKey = null; //
              downStream = parsedProperties;
            }
          }

          info = _parseBlockMap(map, nonExistentKey, downStream);
          node = _trackAnchor(map, mapProps);
        }

      case BlockCollectionEvent.startBlockListEntry when !forceInlined:
        {
          _throwIfNotCompactCompatible(
            parsedProperties,
            parentEnforcedCompactness: parentEnforcedCompactness,
            isBlockSequence: true,
          );

          final list = SequenceDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            start: startOffset,
          );

          info = _parseBlockSequence(list);
          node = _trackAnchor(list, parsedProperties?.properties);
        }

      case BlockCollectionEvent.startExplicitKey when !forceInlined:
        {
          _throwIfNotCompactCompatible(
            parsedProperties,
            parentEnforcedCompactness: parentEnforcedCompactness,
            isBlockSequence: false,
          );

          final map = MappingDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: fixedInlineIndent,
            start: startOffset,
          );

          node = map;
          info = _parseBlockMap(map, null, null);
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

  /// Checks to see if an explicit [_BlockEntry] can be parsed.
  ///
  /// If the entry doesn't start on the next line (inline), the [startOffset]
  /// is used to compute the `inlineIndent` and the `laxIndent` is computed
  /// from the [parentIndent].
  ///
  /// If the entry does start on the next line, the `inlineIndent` and
  /// `laxIndent` are equal. In this case, if the indent `<=` [parentIndent],
  /// then this node cannot be parsed.
  ///
  /// See [_blockChildIndent] implementation.
  _ParseExplicitInfo _explicitIsParsable(int startOffset, int parentIndent) {
    _scanner.skipCharAtCursor(); // Skip the "?" or ":"

    /// Typically exists as "?"<whitespace>. We can't know what/where to
    /// start parsing. Attempt to parsed node properties. The function also
    /// skips to the next possible parsable char
    final properties = _parseNodeProperties(
      _scanner,
      minIndent: parentIndent + 1,
      resolver: _resolveTag,
      comments: _comments,
    );

    // Must be able to parse more characters
    if (!_scanner.canChunkMore) {
      return (
        shouldExit: true,
        hasIndent: false,
        parsedNodeProperties: properties,
        inferredIndent: seamlessIndentMarker,
        laxIndent: seamlessIndentMarker,
        inlineIndent: seamlessIndentMarker,
      );
    }

    final inferredIndent = properties.indentOnExit;
    final hasIndent = inferredIndent != null;

    /// If equal then we are at the same level as a "?" or ":" on a new line.
    /// Anything we moved back a level/several
    if (hasIndent && inferredIndent <= parentIndent) {
      return (
        shouldExit: true,
        hasIndent: hasIndent,
        parsedNodeProperties: properties,
        inferredIndent: inferredIndent,
        laxIndent: inferredIndent,
        inlineIndent: inferredIndent,
      );
    }

    final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
      inferredIndent,
      blockParentIndent: parentIndent,
      startOffset: startOffset,
    );

    return (
      shouldExit: false,
      hasIndent: hasIndent,
      parsedNodeProperties: properties,
      inferredIndent: inferredIndent,
      laxIndent: laxIndent,
      inlineIndent: inlineFixedIndent,
    );
  }

  /// Parses an explicit key. This function is always called by
  /// [_parseExplicitBlockEntry]. You should never call it directly unless
  /// you only need the key!
  (bool shouldExit, _BlockNodeInfo info, ParserDelegate key)
  _parseExplicitBlockKey({required int indentLevel, required int mapIndent}) {
    final keyOffset = _scanner.lineInfo().current;

    final (
      :shouldExit,
      hasIndent: preKeyHasIndent,
      :inferredIndent,
      :parsedNodeProperties,
      :laxIndent,
      :inlineIndent,
    ) = _explicitIsParsable(
      keyOffset.offset,
      mapIndent,
    );

    if (shouldExit && !parsedNodeProperties.properties.isAlias) {
      final endOffset = _scanner.lineInfo();

      // We have an empty/null key on our hands
      return (
        !preKeyHasIndent || inferredIndent! < mapIndent,
        (exitIndent: inferredIndent, hasDocEndMarkers: false),

        _trackAnchor(
            nullScalarDelegate(
              indentLevel: indentLevel,
              indent: mapIndent,
              startOffset: keyOffset,
            ),
            parsedNodeProperties.properties,
          )
          ..updateEndOffset = preKeyHasIndent
              ? endOffset.start
              : endOffset.current,
      );
    }

    /// Our key can either have:
    ///   - Null indent which indicates that the key is declared on the same
    ///     line with the indicator.
    ///   - A larger indent indicates the element is more indented than the
    ///     indicator.
    ///
    /// We don't care (because we don't know how differentiate this). Let the
    /// block node function determine where these indents fit in our grand
    /// scheme of things.
    final (:nodeInfo, :delegate) = _parseBlockNode(
      startOffset: keyOffset,
      indentLevel: indentLevel,
      laxIndent: laxIndent,
      fixedInlineIndent: inlineIndent,
      forceInlined: false,
      isParsingKey: true,
      isExplicitKey: true,
      degenerateToImplicitMap: true,
      parentEnforcedCompactness: true,
      parsedProperties: parsedNodeProperties,
    );

    final (:exitIndent, :hasDocEndMarkers) = nodeInfo;

    final hasIndent = exitIndent != null;

    /// Parsing YAML makes you a skeptic with the layout restrictions.
    ///
    /// A ":" must be declared on a new line while being aligned with the
    /// "?" that triggered this key to be parsed. Thus, their indents
    /// *MUST* match.
    if ((!hasIndent && _scanner.canChunkMore) ||
        (hasIndent && exitIndent > mapIndent)) {
      throw FormatException(
        'Expected ":" on a new line with an indent of $mapIndent space(s) and'
        ' not ${exitIndent ?? 0} space(s)',
      );
    }

    return (
      /// We can exit early if we are no longer at the current map's level
      /// based on the indent (the current map is the caller of this function)
      /// or the current document ended.
      hasDocEndMarkers || !hasIndent || exitIndent < mapIndent,
      nodeInfo,
      delegate,
    );
  }

  /// Parses an explicit block map entry within a block collection declared
  /// using the `?` character.
  _BlockEntry _parseExplicitBlockEntry({
    required int indentLevel,
    required int indent,
  }) {
    // Must have explicit key indicator
    if (_inferNextEvent(
          _scanner,
          isBlockContext: true,
          lastKeyWasJsonLike: false,
        ) !=
        BlockCollectionEvent.startExplicitKey) {
      throw Exception(
        'Expected an explicit key but found ${_scanner.charAtCursor?.string}',
      );
    }

    final childIndentLevel = indentLevel + 1;

    // Attempt to parse key
    final (exitAfterKey, keyNodeInfo, explicitKey) = _parseExplicitBlockKey(
      indentLevel: childIndentLevel,
      mapIndent: indent,
    );

    _blockNodeInfoEndOffset(explicitKey, scanner: _scanner, info: keyNodeInfo);

    if (exitAfterKey) {
      return (
        nodeInfo: keyNodeInfo,
        delegate: (key: explicitKey, value: null),
      );
    }

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
        delegate: (key: explicitKey, value: null),
        nodeInfo: (exitIndent: indent, hasDocEndMarkers: false),
      );
    }

    final valueOffset = _scanner.lineInfo().current;

    // Check if we can parse the value
    final (
      :shouldExit,
      :hasIndent,
      :inferredIndent,
      :parsedNodeProperties,
      :laxIndent,
      :inlineIndent,
    ) = _explicitIsParsable(
      valueOffset.offset,
      indent,
    );

    /// No need to parse the value if we moved to the next line and the
    /// indent matches. Usually means there is no value to parse
    if (shouldExit) {
      ParserDelegate? val;

      if (_nullOrAlias(
            parsedNodeProperties.properties,
            indentLevel: indentLevel,
            indent: indent,
            start: valueOffset,
          )
          case ParserDelegate nullOrAlias) {
        _blockNodeEndOffset(
          nullOrAlias,
          scanner: _scanner,
          hasDocEndMarkers: false,
          indentOnExit: inferredIndent,
        );
        val = nullOrAlias;
      }

      return (
        nodeInfo: (exitIndent: inferredIndent, hasDocEndMarkers: false),
        delegate: (key: explicitKey, value: val),
      );
    }

    final (:delegate, :nodeInfo) = _parseBlockNode(
      startOffset: valueOffset,
      indentLevel: childIndentLevel,
      laxIndent: laxIndent,
      fixedInlineIndent: inlineIndent,
      forceInlined: false,
      isParsingKey: false,
      isExplicitKey: false,
      degenerateToImplicitMap: true,
      parentEnforcedCompactness: true,
      parsedProperties: parsedNodeProperties,
    );

    _blockNodeInfoEndOffset(delegate, scanner: _scanner, info: nodeInfo);
    return (delegate: (key: explicitKey, value: delegate), nodeInfo: nodeInfo);
  }

  /// Parses an implicit block map entry within a block collection.
  _BlockEntry _parseImplicitBlockEntry(
    ParserDelegate? key, {
    required int parentIndent,
    required int parentIndentLevel,
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
        startOffset: _scanner.lineInfo().current,
        event: event,
        indentLevel: parentIndentLevel,
        laxIndent: parentIndent, // Key is the parent's contact in this entry
        fixedInlineIndent: parentIndent,
        forceInlined: true,
        isParsingKey: true,
        isExplicitKey: false,
        degenerateToImplicitMap: false,
        parentEnforcedCompactness: false,

        /// Callers of this [_parseImplicitBlockEntry] function must correctly
        /// handle its node properties. Usually, implicit maps are tightly
        /// controlled. This is evident when:
        ///   1. Parsing block keys - Cannot span multiple lines
        ///   2. Compact notation prevents the implicit maps nested in
        ///      block sequences and explicit block keys from having node
        ///      properties
        ///
        /// Ergo, the callers should never call the [_parseImplicitBlockEntry]
        /// directly unless via [_parseBlockMap] or [_parseBlockNode]. If they
        /// do, they must handle the node properties ahead of time!
        parsedProperties: null,
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
      if (delegate case ScalarDelegate(
        preScalar: PreScalar(
          inferredValue: null,
          scalarStyle: ScalarStyle.plain,
          :final parsedContent,
        ),
      ) when hasDocEndMarkers && parsedContent.isEmpty) {
        return (nodeInfo: nodeInfo, delegate: (key: null, value: null));
      }

      implicitKey = delegate;
    }

    // Must declare ":" on the same line
    if (_skipToParsableChar(_scanner, comments: _comments) != null ||
        nextEvent() != BlockCollectionEvent.startEntryValue) {
      throw FormatException(
        'Expected a ":" (after the key) but found '
        '"${_scanner.charAtCursor?.string}"',
      );
    }

    final valueOffset = _scanner.lineInfo().current;

    implicitKey ??= nullScalarDelegate(
      indentLevel: parentIndentLevel,
      indent: parentIndent,
      startOffset: valueOffset,
    );

    implicitKey.updateEndOffset = valueOffset;

    _scanner.skipCharAtCursor(); // Skip ":"
    var indentOrSeparation = _skipToParsableChar(_scanner, comments: _comments);

    final minValueIndent = parentIndent + 1;
    final valueIndentLevel = parentIndentLevel + 1;

    var childEvent = nextEvent();
    var spanMultipleLines = indentOrSeparation != null;

    /// This is not similar to the [valueOffset]. YAML indicates a value starts
    /// when the ":" is seen; which is fine. However, the node's alignment with
    /// subsequent siblings (in case this node becomes an implicit map) depends
    /// on where it actually starts. Such that:
    ///
    /// key: value
    ///    ^^^ It starts in the first caret but it's alignment must start at "v"
    ///
    /// Now see below:
    ///
    /// ```yaml
    /// key:
    ///   nested: implicit-block-map-as-value
    ///   another: nested
    /// another:
    ///   !!tag key: value
    /// ```
    ///
    /// Our argument is now evident. Our actual content offset starts when we
    /// see the first parsable char. Serves no purpose now but maybe
    /// later?
    ///
    /// TODO: Dumper & editor see this 🧙🏽‍♂️. Explicit too
    final contentOffset = _scanner.lineInfo().current;

    _ParsedNodeProperties? parsedProperties;

    if (childEvent is NodePropertyEvent) {
      parsedProperties = _parseNodeProperties(
        _scanner,
        minIndent: minValueIndent,
        resolver: _resolveTag,
        comments: _comments,
      );

      spanMultipleLines = parsedProperties.isMultiline;
      indentOrSeparation = parsedProperties.indentOnExit;
      childEvent = nextEvent();
    }

    // Nothing available
    if (!_scanner.canChunkMore) {
      return (
        delegate: (
          key: implicitKey,

          /// Coin toss. We either have a null value or it's an alias if we
          /// have any props :)
          value: _nullOrAlias(
            parsedProperties?.properties,
            indentLevel: valueIndentLevel,
            indent: minValueIndent,
            start: valueOffset,
          )?..updateEndOffset = _scanner.lineInfo().current,
        ),
        nodeInfo: _emptyScanner,
      );
    }

    final isBlockList = childEvent == BlockCollectionEvent.startBlockListEntry;

    /// YAML 1.2 recommends grace for block lists that start on a new line but
    /// have the same indent as the implicit key since the "-" is usually
    /// perceived as indent.
    if (spanMultipleLines) {
      if (indentOrSeparation != null &&
          ((indentOrSeparation == parentIndent && !isBlockList) ||
              (indentOrSeparation < parentIndent))) {
        return (
          delegate: (key: implicitKey, value: null),
          nodeInfo: (hasDocEndMarkers: false, exitIndent: indentOrSeparation),
        );
      }
    } else if ((isBlockList ||
        childEvent == BlockCollectionEvent.startExplicitKey)) {
      throw FormatException(
        'The block collections must start on a new line when used as values of '
        'an implicit key',
      );
    }

    final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
      indentOrSeparation,
      blockParentIndent: parentIndent,
      startOffset: contentOffset.offset,
    );

    final (
      :delegate,
      nodeInfo: _BlockNodeInfo(:hasDocEndMarkers, :exitIndent),
    ) = _parseBlockNode(
      startOffset: valueOffset,
      indentLevel: valueIndentLevel,
      laxIndent: laxIndent,
      fixedInlineIndent: inlineFixedIndent,
      forceInlined: false,
      isParsingKey: false,
      isExplicitKey: false,
      degenerateToImplicitMap: spanMultipleLines, // Only if not inline
      parentEnforcedCompactness: false,
      parsedProperties: parsedProperties,
      event: childEvent,
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
  (SourceLocation? offset, _ParsedNodeProperties? properties) _throwIfDangling(
    int collectionIndent,
    int currentIndent, {
    required bool allowProperties,
  }) {
    final isNodeEvent =
        _inferNextEvent(
              _scanner,
              isBlockContext: true,
              lastKeyWasJsonLike: false,
            )
            is NodePropertyEvent;

    if (currentIndent > collectionIndent && _scanner.canChunkMore) {
      throw FormatException(
        'Dangling node/node properties found with indent of $currentIndent'
        ' space(s) while parsing',
      );
    } else if (isNodeEvent) {
      if (!allowProperties) {
        throw FormatException(
          'Dangling node properties found at '
          '${_scanner.lineInfo().current.offset}',
        );
      }

      final offset = _scanner.lineInfo().current;

      return (
        offset,
        _parseNodeProperties(
          _scanner,
          minIndent: collectionIndent + 1,
          resolver: _resolveTag,
          comments: _comments,
        ),
      );
    }

    return (null, null);
  }

  /// Parses a block map. If [firstImplicitKey] is present, the map parses
  /// only the value of the first key.
  _BlockNodeInfo _parseBlockMap(
    MappingDelegate map,
    ParserDelegate? firstImplicitKey,
    _ParsedNodeProperties? parsedProperties,
  ) {
    var parsedKey = firstImplicitKey;
    final MappingDelegate(:indent, :indentLevel) = map;

    var properties = parsedProperties;
    NodeProperties? nodeProps;
    SourceLocation? implicitStartOffset;

    void resetProps(_ParsedNodeProperties? props, SourceLocation? offset) {
      properties = props;
      implicitStartOffset = offset;
      nodeProps = null;
    }

    void throwIfDanglingProps() {
      if (properties != null) {
        throw FormatException(
          'Dangling node properties found while exiting block map',
        );
      }
    }

    while (_scanner.canChunkMore) {
      ParserDelegate? key;
      ParserDelegate? value;
      _BlockNodeInfo mapInfo;

      final (
        :event,
        :hasProperties,
        :blockMapContinue,
        :isExplicitEntry,
        :indentOnExit,
      ) = _checkMapState(
        properties,
        isBlockContext: true,
        minMapIndent: indent,
      );

      if (!blockMapContinue) {
        throw FormatException(
          'Incomplete block map at ${_scanner.lineInfo().current.offset}',
        );
      }

      if (isExplicitEntry) {
        final (:delegate, :nodeInfo) = _parseExplicitBlockEntry(
          indentLevel: indentLevel,
          indent: indent,
        );

        mapInfo = nodeInfo;
        key = delegate.key;
        value = delegate.value;
      } else {
        // Implicit keys restricted to a single line
        if (hasProperties) {
          final _ParsedNodeProperties(properties: dProps) = properties!;

          parsedKey = _aliasKeyOrNull(
            dProps,
            indentLevel: indentLevel,
            indent: indent,
            keyStartOffset: implicitStartOffset!,
            existing: parsedKey,
          );

          nodeProps = dProps;
        }

        final (:delegate, :nodeInfo) = _parseImplicitBlockEntry(
          parsedKey,
          parentIndent: indent,
          parentIndentLevel: indentLevel,
          mapEvent: event,
        );

        mapInfo = nodeInfo;
        key = delegate.key;
        value = delegate.value;
      }

      /// Most probably encountered doc end chars while parsing implicit map.
      /// An explicit key should never return null here
      if (key == null) {
        throwIfDanglingProps();
        _blockNodeInfoEndOffset(map, scanner: _scanner, info: mapInfo);
        return mapInfo;
      }

      _trackAnchor(key, nodeProps);

      if (!map.pushEntry(key, value)) {
        throw FormatException(
          'Block map cannot contain entries sharing the same key',
        );
      }

      final (:hasDocEndMarkers, :exitIndent) = mapInfo;

      /// Update end offset. We must always have the correct end offset
      /// independent of the last node.
      _blockNodeEndOffset(
        map,
        scanner: _scanner,
        hasDocEndMarkers: hasDocEndMarkers,
        indentOnExit: exitIndent,
      );

      if (hasDocEndMarkers) {
        return mapInfo;
      }

      /// If no doc end chars were found, indent on exit *MUST* not be null.
      /// Block collections rely only on indent as delimiters
      if (exitIndent == null) {
        if (_scanner.canChunkMore) {
          throw FormatException(
            'Invalid map entry found at while parsing block map',
          );
        }

        resetProps(null, null);
        break;
      } else if (exitIndent < indent) {
        return mapInfo;
      }

      // Must not have a dangling indent or properties at this point
      final (indentOnProps, props) = _throwIfDangling(
        indent,
        exitIndent,
        allowProperties: true,
      );

      resetProps(props, indentOnProps);
      parsedKey = null;
    }

    throwIfDanglingProps();
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
        indicator
            when charAfter == null ||
                charAfter is WhiteSpace ||
                charAfter is LineBreak =>
          false,

        _ => throw FormatException(
          'Expected a "- " while parsing sequence but found "${char?.string}'
          '${charAfter?.string}"',
        ),
      };
    }

    final childIndentLevel = indentLevel + 1;

    /// Always want it run the first time. We need that first empty node
    /// with the "-<null>" pattern
    do {
      if (exitOrThrowIfNotBlock()) {
        return (hasDocEndMarkers: true, exitIndent: null);
      }

      final startOffset = _scanner.lineInfo().current;

      _scanner.skipCharAtCursor(); // Skip "-"

      final parsedProps = _parseNodeProperties(
        _scanner,
        minIndent: indent + 1,
        resolver: _resolveTag,
        comments: _comments,
      );

      final indentOrSeparation = parsedProps.indentOnExit;

      if (!_scanner.canChunkMore) break;

      if (indentOrSeparation != null) {
        final isLess = indentOrSeparation < indent;

        // We moved to the next node irrespective of its indent.
        if (isLess || indentOrSeparation == indent) {
          final entry =
              _nullOrAlias(
                parsedProps.properties,
                indentLevel: indentLevel,
                indent: indent,
                start: startOffset,
              ) ??
              nullScalarDelegate(
                indentLevel: childIndentLevel,
                indent: indent + 1,
                startOffset: startOffset,
              );

          sequence.pushEntry(
            entry..updateEndOffset = _scanner.lineInfo().start,
          );

          // Not a skill issue. 2 birds, 1 stone
          if (isLess) {
            return (exitIndent: indentOrSeparation, hasDocEndMarkers: false);
          }

          continue;
        }
      }

      // Determine indentation of child node
      final (:laxIndent, :inlineFixedIndent) = _blockChildIndent(
        indentOrSeparation,
        blockParentIndent: indent,
        startOffset: startOffset.offset,
      );

      final (:delegate, :nodeInfo) = _parseBlockNode(
        startOffset: startOffset,
        indentLevel: childIndentLevel,
        laxIndent: laxIndent,
        fixedInlineIndent: inlineFixedIndent,
        forceInlined: false,
        isParsingKey: false,
        isExplicitKey: false,
        degenerateToImplicitMap: true,
        parentEnforcedCompactness: true,
        parsedProperties: parsedProps,
      );

      sequence.pushEntry(delegate);

      final (:hasDocEndMarkers, :exitIndent) = nodeInfo;

      // Update offset of sequence. May span more than the last node
      _blockNodeEndOffset(
        sequence,
        scanner: _scanner,
        hasDocEndMarkers: hasDocEndMarkers,
        indentOnExit: exitIndent,
      );

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
      _throwIfDangling(indent, exitIndent, allowProperties: false);
    } while (_scanner.canChunkMore);

    return _emptyScanner;
  }

  /// Parses a root flow mapping or sequence.
  CollectionDelegate _parseRootFlow(
    FlowCollectionEvent event, {
    required SourceLocation rootStartOffset,
    required int rootIndentLevel,
    required int rootIndent,
  }) {
    switch (event) {
      case FlowCollectionEvent.startFlowMap:
        {
          final map = MappingDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: rootIndentLevel,
            indent: rootIndent,
            start: rootStartOffset,
          );

          _parseFlowMap(map, forceInline: false);
          return map;
        }

      case FlowCollectionEvent.startFlowSequence:
        {
          final sequence = SequenceDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: rootIndentLevel,
            indent: rootIndent,
            start: rootStartOffset,
          );

          _parseFlowSequence(sequence, forceInline: false);

          return sequence;
        }

      default:
        throw FormatException(
          'Leading "," "}" or "]" flow indicators found with no'
          ' opening "[" "{"',
        );
    }
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
      final (
        :yamlDirective,
        :globalTags,
        :reservedDirectives,
        :hasDirectiveEnd,
      ) = parseDirectives(
        _scanner,
      );

      _hasDirectives =
          yamlDirective != null ||
          globalTags.isNotEmpty ||
          reservedDirectives.isNotEmpty;

      _docStartExplicit = hasDirectiveEnd;

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

    /// Why block info? YAML clearly has a favourite child and that is the
    /// block(-like) styles. They are indeed a human friendly format. Also, the
    /// doc end chars "..." and "---" exist in this format.
    ParserDelegate? root;
    _BlockNodeInfo? rootInfo;
    _ParsedNodeProperties? parsedProperties;

    const rootIndentLevel = 0;
    var rootIndent = _skipToParsableChar(_scanner, comments: _comments);
    final rootStartOffset = _scanner.lineInfo().current;

    var rootEvent = _inferNextEvent(
      _scanner,
      isBlockContext: true, // Always prefer block styling over flow
      lastKeyWasJsonLike: false,
    );

    if (rootEvent is NodePropertyEvent) {
      parsedProperties = _parseNodeProperties(
        _scanner,

        // Default to "-1" if we have no node in place.
        minIndent: rootIndent ?? -1,
        resolver: _resolveTag,
        comments: _comments,
      );

      if (parsedProperties.properties.isAlias) {
        throw FormatException('Root node cannot be an alias!');
      }

      rootEvent = _inferNextEvent(
        _scanner,
        isBlockContext: true,
        lastKeyWasJsonLike: false,
      );

      rootIndent = parsedProperties.indentOnExit;
    }

    rootIndent ??= 0; // Defaults to zero if null

    _throwIfUnsafeForDirectiveChar(
      _scanner.charAtCursor,
      //indent: rootIndent,
      isDocStartExplicit: _docStartExplicit,
      hasDirectives: _hasDirectives,
    );

    if (rootEvent case FlowCollectionEvent event) {
      final key = _parseRootFlow(
        event,
        rootStartOffset: rootStartOffset,
        rootIndentLevel: rootIndentLevel,
        rootIndent: rootIndent,
      );

      /// As indicated initially, YAML considerably favours block(-like)
      /// styles. This flow collection may be an implicit key if only it
      /// is inline and we see a ": " char combination ahead.
      ///
      /// Also implicit maps cannot start on "---" line
      if (!_rootInMarkerLine &&
          !key.encounteredLineBreak &&
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
        NodeProperties? props;

        if (parsedProperties != null) {
          final _ParsedNodeProperties(:isMultiline, :properties) =
              parsedProperties;

          if (!isMultiline) {
            _trackAnchor(key, properties);
          } else {
            props = properties;
          }
        }

        final (
          delegate: (key: _, :value),
          :nodeInfo,
        ) = _parseImplicitBlockEntry(
          key,
          parentIndent: rootIndent,
          parentIndentLevel: rootIndentLevel,
        );

        final lineInfo = _scanner.lineInfo();

        root =
            MapEntryDelegate(
                nodeStyle: NodeStyle.block,
                keyDelegate: key,
              )
              ..updateValue = value
              ..updateEndOffset = nodeInfo.hasDocEndMarkers
                  ? lineInfo.start
                  : lineInfo.current
              ..updateNodeProperties = props;

        rootInfo = nodeInfo;
      } else {
        root = key..updateNodeProperties = parsedProperties?.properties;
      }
    } else {
      final (:delegate, :nodeInfo) = _parseBlockNode(
        event: rootEvent,
        startOffset: rootStartOffset,
        indentLevel: rootIndentLevel,
        laxIndent: rootIndent,
        fixedInlineIndent: rootIndent,
        forceInlined: false,
        isParsingKey: false, // No effect if explicit. Handled
        isExplicitKey: false,
        degenerateToImplicitMap: !_rootInMarkerLine,
        parentEnforcedCompactness: false,
        parsedProperties: parsedProperties,
      );

      root = delegate;
      rootInfo = nodeInfo;
    }

    if (_scanner.canChunkMore) {
      /// We must see document end chars and don't care how they are laid within
      /// the document. At this point the document is or should be complete
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
      root.updateEndOffset = _scanner.lineInfo().start;
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
}
