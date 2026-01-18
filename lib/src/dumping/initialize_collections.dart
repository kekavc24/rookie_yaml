part of 'object_dumper.dart';

/// Calls [ifBlock] or [ifFlow] if [style] is [NodeStyle.block] or
/// [NodeStyle.flow] respectively.
T _initialize<T>(
  NodeStyle style, {
  required T Function() ifBlock,
  required T Function() ifFlow,
}) => switch (style) {
  NodeStyle.block => ifBlock(),
  _ => ifFlow(),
};

/// Calls [ifThis] only if [style] is [NodeStyle.block].
void _isBlock(NodeStyle style, void Function() ifThis) => _initialize(
  style,
  ifBlock: ifThis,
  ifFlow: () {},
);

/// Initializes an [IterableDumper] and a [MapDumper] that are compatible since
/// YAML does not allow [NodeStyle.block] to be used in [NodeStyle.flow].
(IterableDumper list, MapDumper map) _initializeCollections({
  required Compose onObject,
  required PushAnchor pushAnchor,
  required AsLocalTag asLocalTag,
  required ScalarDumper scalar,
  required CommentDumper comments,
  required bool flowIterableInline,
  required bool flowMapInline,
  required NodeStyle sequenceStyle,
  required NodeStyle mappingStyle,
}) {
  // Force both as block if scalars are block.
  final (
    iterableStyle,
    mapStyle,
  ) = scalar.defaultStyle.nodeStyle == NodeStyle.block
      ? (NodeStyle.block, NodeStyle.block)
      : (sequenceStyle, mappingStyle);

  final mapDumper = _initialize<MapDumper>(
    mapStyle,
    ifBlock: () => MapDumper.block(
      scalarDumper: scalar,
      commentDumper: comments,
      onObject: onObject,
      pushAnchor: pushAnchor,
      asLocalTag: asLocalTag,
    ),
    ifFlow: () => MapDumper.flow(
      preferInline: flowMapInline,
      scalarDumper: scalar,
      commentDumper: comments,
      onObject: onObject,
      pushAnchor: pushAnchor,
      asLocalTag: asLocalTag,
    ),
  );

  final iterableDumper = _initialize<IterableDumper>(
    iterableStyle,
    ifBlock: () => IterableDumper.block(
      scalarDumper: scalar,
      commentDumper: comments,
      onObject: onObject,
      pushAnchor: pushAnchor,
      asLocalTag: asLocalTag,
    ),
    ifFlow: () => IterableDumper.flow(
      preferInline: flowIterableInline,
      scalarDumper: scalar,
      commentDumper: comments,
      onObject: onObject,
      pushAnchor: pushAnchor,
      asLocalTag: asLocalTag,
    ),
  );

  if (iterableStyle == mapStyle) {
    return (
      iterableDumper..mapDumper = mapDumper,
      mapDumper..iterableDumper = iterableDumper,
    );
  }

  // Block nodes can have flow nodes but the reverse is not true.
  _isBlock(iterableStyle, () => iterableDumper.mapDumper = mapDumper);
  _isBlock(mapStyle, () => mapDumper.iterableDumper = iterableDumper);

  return (iterableDumper, mapDumper);
}
