import 'package:rookie_yaml/src/yaml_nodes/node_styles.dart';

abstract base class Node {
  Node({required this.nodeStyle});

  final NodeStyle nodeStyle;
}

final class Sequence extends Node {
  Sequence({required CollectionStyle style}) : super(nodeStyle: style);

  final nodes = <Node>[];
}

final class Mapping extends Node {
  Mapping({required CollectionStyle style}) : super(nodeStyle: style);

  final entries = <Node, Node>{};
}

final class Scalar extends Node {
  Scalar({required this.scalarStyle, required this.content})
    : super(nodeStyle: scalarStyle.nodeStyle);

  final ScalarStyle scalarStyle;

  final String content;
}
