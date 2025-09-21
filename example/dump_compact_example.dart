import 'package:rookie_yaml/rookie_yaml.dart';

final class Fancy<T> implements CompactYamlNode {
  Fancy({
    this.value,
    this.alias,
    this.anchor,
    this.tag,
    NodeStyle? style,
  }) : nodeStyle = style ?? NodeStyle.flow;

  final T? value;

  @override
  final String? alias;

  @override
  final String? anchor;

  @override
  final NodeStyle nodeStyle;

  @override
  final ResolvedTag? tag;
}

void main(List<String> args) {
  Object unpacker(Fancy fancy) => fancy.value;

  final object = Fancy(
    value: [
      Fancy(value: 24, anchor: 'int'),
      Fancy(alias: 'int'),
    ],
    style: NodeStyle.block,
  );

  ///
  /// %YAML 1.2
  /// ---
  /// - &int 24
  /// - *int
  print(
    dumpCompactNode<Fancy<dynamic>>(
      object,
      nodeUnpacker: unpacker,
      scalarStyle: ScalarStyle.plain,
    ),
  );

  ///
  /// %YAML 1.2
  /// ---
  /// !tag {
  ///  key: [
  ///    &int 24,
  ///    *int
  ///   ]
  /// }
  print(
    // With tag. Must be encoded as flow map
    dumpCompactNode<Fancy<dynamic>>(
      Fancy(
        value: {'key': object},
        tag: NodeTag(
          TagShorthand.fromTagUri(TagHandle.primary(), 'tag'),
          null,
        ),
      ),
      nodeUnpacker: unpacker,
    ),
  );
}
