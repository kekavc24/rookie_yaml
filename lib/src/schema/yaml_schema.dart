import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Default `YAML` uri prefix
const _yamlPrefix = 'tag:yaml.org,2002:';

/// Default handle for the global `YAML` tag.
///
/// See [_yamlPrefix]
final _defaultYamlHandle = TagHandle.secondary();

/// `YAML` global tag
///
/// ```text
/// %TAG !! tag:yaml.org,2002:
/// ```
final yamlGlobalTag = GlobalTag.fromTagUri(_defaultYamlHandle, _yamlPrefix);

/// Generic [Map]
final mappingTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'map');

/// Generic [List]
final sequenceTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'seq');

/// Generic [String]
final stringTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'str');

//
// ** JSON SCHEMA TAGS **
// This schema is supported by YAML out of the box.
//

/// `JSON` `null`
final nullTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'null');

/// `JSON` [bool]
final booleanTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'bool');

/// `JSON` [int]
final integerTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'int');

/// `JSON` [double]
final floatTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'float');

//
// ** Dart Tags **
//

/// [Uri] tag
final uriTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'uri');

/// Any [TagShorthand] that resolves to a [Scalar]
final scalarTags = {
  stringTag,
  nullTag,
  booleanTag,
  integerTag,
  floatTag,
  uriTag,
};

/// Checks if a [tag] is valid tag in the yaml schema. A yaml tag uses the
/// [TagHandleVariant.secondary] handle
bool isYamlTag(TagShorthand tag) =>
    tag == mappingTag || tag == sequenceTag || scalarTags.contains(tag);
