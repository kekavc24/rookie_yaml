import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';

/// A visitor for built-in Dart types.
mixin DartTypeVisitor {
  /// Visits an [object] and redirects it to the appropriate visitor function.
  void visitObject(Object? object) => switch (object) {
    Map() => visitMap(object),
    Iterable() => visitIterable(object),
    _ => visitScalar(object),
  };

  /// Visits a [scalar].
  void visitScalar(Object? scalar);

  /// Visits a [map].
  void visitMap(Map<Object?, Object?> map);

  /// Visits an [iterable].
  void visitIterable(Iterable<Object?> iterable);
}

/// A visitor for a [DumpableView].
mixin ViewVisitor {
  /// Visits a generic [view] and redirects it to the appropriate visitor
  /// function.
  void visitView(DumpableView view) => switch (view) {
    YamlMapping() => visitMappingView(view),
    YamlIterable() => visitIterableView(view),
    ScalarView() => visitScalarView(view),
    _ => visitAlias(view as Alias),
  };

  /// Visits an [alias].
  void visitAlias(Alias alias);

  /// Visits a [scalar].
  void visitScalarView(ScalarView scalar);

  /// Visits an [iterable]
  void visitIterableView(YamlIterable iterable);

  /// Visits a [mapping].
  void visitMappingView(YamlMapping mapping);
}

// mixin EventTreeVisitor {
//   void visitEventTree(TreeNode<Object> treeNode) {
//     switch (treeNode.nodeType) {}
//   }

//   void visitAliasNode(ReferenceNode alias);

//   // void visit
// }
