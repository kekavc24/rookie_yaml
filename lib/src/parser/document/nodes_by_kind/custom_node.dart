import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_sequence.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

part 'custom_block_node.dart';
part 'custom_flow_node.dart';

/// Parses a node annotated with a custom property. The resolver within the
/// [property] is extracted.
///
/// [onMatchScalar] receives the actual resolver.
///
/// [onMatchMap] and [onMatchIterable] receive their builder functions since a
/// map and iterable must be instantiated before they can accepts node being
/// parsed.
T _parseCustomKind<T, Obj>(
  CustomKind kind, {
  required NodeProperty property,
  required T Function(OnCustomMap<Obj> mapBuilder) onMatchMap,
  required T Function(OnCustomList<Obj> listBuilder) onMatchIterable,
  required T Function(ObjectFromScalarBytes<Obj> resolver) onMatchScalar,
}) {
  final resolver = property.customResolver!;

  return switch (kind) {
    CustomKind.map => onMatchMap((resolver as ObjectFromMap<Obj>).onCustomMap),
    CustomKind.iterable => onMatchIterable(
      (resolver as ObjectFromIterable<Obj>).onCustomIterable,
    ),
    _ => onMatchScalar(resolver as ObjectFromScalarBytes<Obj>),
  };
}

typedef OnCompleteCustom<R, T> =
    R Function(
      ScalarStyle style,
      int indentOnExit,
      bool indentDidChange,
      DocumentMarker marker,
      NodeDelegate<T> delegate,
    );

/// Parses a scalar using a custom [resolver].
///
/// This function is quite similar to the default scalar implementation used
/// by the parser. However, this function prefers a more mechanical approach
/// and calls the low level parse functions that read directly from the
/// [iterator].
///
/// [onScalar] is only called after the `onComplete` callback provided in the
/// [resolver] has been called.
R parseCustomScalar<R, Obj>(
  ScalarEvent event, {
  required SourceIterator iterator,
  required ObjectFromScalarBytes<Obj> resolver,
  required NodeProperty property,
  required void Function(YamlComment comment) onParseComment,
  required OnCompleteCustom<R, Obj> onScalar,
  required bool isImplicit,
  required bool isInFlowContext,
  required int indentLevel,
  required int minIndent,
}) {
  // Delegate helper.
  BoxedScalar<Obj> delegateOf(ScalarStyle style) {
    return BoxedScalar(
      resolver.onCustomScalar(),
      scalarStyle: style,
      indentLevel: indentLevel,
      indent: minIndent,
      start: property.span.start,
    );
  }

  // Creates the scalar and calls [onComplete].
  R completionHelper(BoxedScalar<Obj> boxed, ParsedScalarInfo info) {
    boxed.delegate.onComplete();
    final (
      :scalarStyle,
      :scalarIndent,
      :hasLineBreak,
      :docMarkerType,
      :indentOnExit,
      :indentDidChange,
      :end,
    ) = info;

    return onScalar(
      scalarStyle,
      indentOnExit,
      indentDidChange,
      docMarkerType,
      boxed
        ..indent = scalarIndent
        ..hasLineBreak = hasLineBreak
        ..updateEndOffset = end,
    );
  }

  // Handler for the parser.
  R parse(ScalarStyle style, R Function(BoxedScalar<Obj> delegate) parser) {
    final delegate = delegateOf(style);
    return parser(delegate);
  }

  var isFolded = false;

  switch (event) {
    case ScalarEvent.startBlockFolded when !isImplicit && !isInFlowContext:
      {
        isFolded = true;
        continue block;
      }

    block:
    case ScalarEvent.startBlockLiteral when !isImplicit && !isInFlowContext:
      {
        return parse(
          isFolded ? ScalarStyle.folded : ScalarStyle.literal,
          (d) => blockScalarParser(
            iterator,
            charBuffer: d.delegate.onWriteRequest,
            minimumIndent: minIndent,
            indentLevel: indentLevel,
            onParseComment: onParseComment,
            onParsingComplete: (info) => completionHelper(d, info),
          ),
        );
      }

    case ScalarEvent.startFlowDoubleQuoted:
      {
        return parse(
          ScalarStyle.doubleQuoted,
          (d) => doubleQuotedParser(
            iterator,
            buffer: d.delegate.onWriteRequest,
            indent: minIndent,
            isImplicit: isImplicit,
            onParsingComplete: (info) => completionHelper(d, info),
          ),
        );
      }

    case ScalarEvent.startFlowSingleQuoted:
      {
        return parse(
          ScalarStyle.singleQuoted,
          (d) => singleQuotedParser(
            iterator,
            buffer: d.delegate.onWriteRequest,
            indent: minIndent,
            isImplicit: isImplicit,
            onParsingComplete: (info) => completionHelper(d, info),
          ),
        );
      }

    case _ when event == ScalarEvent.startFlowPlain:
      {
        // Plain scalars may return null
        final plainDelegate = delegateOf(ScalarStyle.plain);

        final plain = plainParser(
          iterator,
          buffer: plainDelegate.delegate.onWriteRequest,
          indent: minIndent,
          charsOnGreedy: '',
          isImplicit: isImplicit,
          isInFlowContext: isInFlowContext,
          onParsingComplete: (info) => completionHelper(plainDelegate, info),
        );

        if (plain == null) {
          throwWithRangedOffset(
            iterator,
            message:
                'Dirty parser state. Failed to parse a custom plain scalar',
            start: plainDelegate.start,
            end: iterator.currentLineInfo.current,
          );
        }

        return plain;
      }

    default:
      throwWithRangedOffset(
        iterator,
        message: 'Dirty parser state. Failed to parse a scalar using $event.',
        start: property.span.start,
        end: iterator.currentLineInfo.current,
      );
  }
}
