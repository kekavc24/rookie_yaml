import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';

/// A map with functions linked to a local tag.
typedef Resolvers = Map<TagShorthand, ResolverCreator<Object?>>;

/// A map with [CustomResolver]s associated with a local tag.
typedef AdvancedResolvers = Map<TagShorthand, CustomResolver>;

/// A class with callbacks to some of the inner workings of the parser.
abstract base class CustomTriggers {
  const CustomTriggers({
    Resolvers? resolvers,
    AdvancedResolvers? advancedResolvers,
  }) : _resolvers = resolvers,
       _advancedResolvers = advancedResolvers;

  /// Custom functions to resolve a scalar's string content based on the
  /// [TagShorthand].
  final Resolvers? _resolvers;

  /// Custom resolvers that instantiate custom delegates used by the actual
  /// parser based on the [TagShorthand].
  final AdvancedResolvers? _advancedResolvers;

  /// Triggered when the parser parses a valid mapping key and always before
  /// its value is parsed.
  void onParsedKey(Object? key);

  /// Triggered when the parser starts parsing a document within a yaml source
  /// string.
  void onDocumentStart(int index);

  /// Obtains a custom resolver that instantiates custom object delegates.
  /// Called before [onScalarResolver] when a local tag is being resolved to a
  /// global tag.
  ///
  /// This allows you to lazily bind a [localTag] to  specific custom resolver
  /// with a custom delegate implementation. However, you must be careful
  /// since a [CustomResolver] forces the parser to expect a specific node kind
  /// and may throw if such a node kind cannot be parsed using the current
  /// YAML source string state.
  CustomResolver? onCustomResolver(TagShorthand localTag) =>
      _advancedResolvers?[localTag];

  /// Obtains a scalar resolver that maps a scalar's content to a custom type.
  /// Called after [onCustomResolver] when a local tag is being resolved to a
  /// global tag only if it returns `null`.
  ///
  /// This allows you lazily bind a [localTag] to custom mapping function.
  /// Unlike [onCustomResolver], the mapping function is embedded within a
  /// resolver tag that the parser has control over. If the [localTag] does
  /// not belong to a scalar, the parser ignores the mapping function and
  /// assigns the tag to the node if the tag matches the node's kind or has a
  /// primary/named handle or is a custom tag.
  ResolverCreator<Object?>? onScalarResolver(TagShorthand localTag) =>
      _resolvers?[localTag];

  /// Triggered when the parser requires a generic sequence delegate when no
  /// tags are present.
  OnCustomList<S>? onDefaultSequence<S>() => null;

  /// Triggered when the parser requires a generic mapping delegate when no
  /// tags are present. This could be used to return custom objects for
  /// top-level and nested mappings if paired correctly with [onParsedKey].
  OnCustomMap<M>? onDefaultMapping<M>() => null;
}
