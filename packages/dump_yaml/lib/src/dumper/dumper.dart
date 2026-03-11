import 'dart:collection';

import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/visitor.dart';
import 'package:dump_yaml/src/utils.dart';

part 'inline_flow_dumper.dart';

/// A generic YAML Dumper.
sealed class Dumper<T> with TreeNodeVisitor {
  /// Dumps a [node].
  void dump(T node);

  /// Dumped string.
  String dumped();
}
