part of 'yaml_node.dart';

/// Represents an object that can be used as a wrapper for any data class.
final class JsonNodeToYaml<T> extends YamlNode {
  JsonNodeToYaml._(this.generator, {NodeStyle? style})
    : nodeStyle = style ?? NodeStyle.flow;

  JsonNodeToYaml.fromFunction({
    required T Function() generator,
    NodeStyle? style,
  }) : this._(generator, style: style);

  JsonNodeToYaml.fromObject(T object, [NodeStyle? style])
    : this.fromFunction(generator: () => object, style: style);

  /// A `toJson` closure or a valid object that can be dumped to yaml
  final T Function() generator;

  @override
  final NodeStyle nodeStyle;
}

/// A simple wrapper for most `Dart` types. Effective if you want to access
/// keys in a [Mapping]
final class DartNode<T> extends YamlNode {
  DartNode(T dartValue)
    : assert(
        dartValue != YamlNode,
        'Expected a Dart type that is not a YamlNode',
      ),
      value = dartValue;

  /// Wrapped value
  final T value;

  @override
  NodeStyle get nodeStyle => NodeStyle.block;

  @override
  bool operator ==(Object other) => _equality.equals(other, value);

  @override
  int get hashCode => _equality.hash(value);
}

/// Represents an interface for the `YAML` junkies. #BYOYaml
///
/// This class is great if you want to declare custom properties. The
/// correctness of the yaml you provide should be tested!
abstract interface class DirectToYaml extends YamlNode {
  /// Sequence of lines in the custom source string. Lines will be joined
  /// by a linefeed (`\n`)
  Iterable<String> get linesToDump;

  /// `CSS` what what ;). [linesToDump] are dumped vertically.
  @override
  NodeStyle get nodeStyle => NodeStyle.block;
}
