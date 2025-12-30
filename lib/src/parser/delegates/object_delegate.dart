import 'dart:collection';
import 'dart:typed_data';

import 'package:rookie_yaml/src/parser/delegates/one_pass_scalars/efficient_scalar_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

part 'map_like_delegate.dart';
part 'node_delegate.dart';
part 'scalar_like_delegate.dart';
part 'sequence_like_delegate.dart';

/// Creates a default [NodeTag] with the [yamlGlobalTag] as its prefix. [tag]
/// must be a secondary tag.
NodeTag _defaultTo(TagShorthand tag) => NodeTag(yamlGlobalTag, tag);

/// Overrides the [current] node tag to a [kindDefault] if [current] is
/// non-specific.
NodeTag _overrideNonSpecific(NodeTag current, TagShorthand kindDefault) {
  if (!current.suffix.isNonSpecific) return current;

  // No need to override if the non-specific tag has a global tag prefix
  return current.resolvedTag is GlobalTag ? current : _defaultTo(kindDefault);
}

/// A constructor for any object that delegates its builder to a
/// [NodeDelegate].
typedef YamlObjectBuilder<S, I, O> =
    O Function(
      I object,
      S objectStyle,
      ResolvedTag? tag,
      String? anchor,
      RuneSpan nodeSpan,
    );

/// A constructor for collection-like builders.
typedef YamlCollectionBuilder<I, O> = YamlObjectBuilder<NodeStyle, I, O>;

/// A builder function for [List] or [Sequence].
typedef ListFunction<I> = YamlCollectionBuilder<Iterable<I>, I>;

/// A builder function for [Map] or [Mapping]
typedef MapFunction<I> = YamlCollectionBuilder<Map<I, I?>, I>;

/// A builder function for a scalar or a Dart built-in type that is not a [Map]
/// or [List]
typedef ScalarFunction<T> =
    YamlObjectBuilder<ScalarStyle, ScalarValue<Object?>, T>;

/// A builder function for an [Alias] or any referenced Dart-built in type.
typedef AliasFunction<Ref> =
    Ref Function(String alias, Ref reference, RuneSpan nodeSpan);

/// A class that represent a generic node parsed from a YAML source string.
sealed class ObjectDelegate<T> {
  /// Node's property.
  ParsedProperty? _property;

  /// Whether any properties are present
  bool get hasProperty => _property != null;

  /// Property obtained from a YAML source string if present.
  ///
  /// Internal parser delegates set this property to `null` after a node has
  /// been resolved since it's information is no longer required. However, this
  /// property is persisted if an external delegate is provided to the parser
  /// since external types do not have access to this information.
  ParsedProperty? get property => _property;

  /// Resolves the object [T].
  T parsed();
}

/// Helper mixin that normalizes the local tag information assigned to an
/// [ObjectDelegate].
mixin TagInfo<T> on ObjectDelegate<T> {
  /// Obtains the resolved local tag information associated with each object.
  /// Always returns `null` for any alias or object having a [VerbatimTag].
  ({GlobalTag? globalTag, TagShorthand suffix})? localTagInfo() {
    final objectTag = switch (_property) {
      NodeProperty(tag: final ResolvedTag resolved) => resolved,
      _ => null,
    };

    if (objectTag case null || VerbatimTag()) return null;

    // All objects have this tag.
    final NodeTag(
      :resolvedTag,
      :suffix,
      :hasGlobalTag,
    ) = objectTag is ContentResolver
        ? objectTag.resolvedTag
        : objectTag as NodeTag;

    return (
      globalTag: hasGlobalTag ? resolvedTag as GlobalTag : null,
      suffix: suffix,
    );
  }
}
