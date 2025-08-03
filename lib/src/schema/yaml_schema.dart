import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

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
final mappingTag = LocalTag.fromTagUri(_defaultYamlHandle, 'map');

/// Generic [List]
final sequenceTag = LocalTag.fromTagUri(_defaultYamlHandle, 'seq');

/// Generic [String]
final stringTag = LocalTag.fromTagUri(_defaultYamlHandle, 'str');

//
// ** JSON SCHEMA TAGS **
// This schema is supported by YAML out of the box.
//

/// `JSON` [null]
final nullTag = LocalTag.fromTagUri(_defaultYamlHandle, 'null');

/// `JSON` [bool]
final booleanTag = LocalTag.fromTagUri(_defaultYamlHandle, 'bool');

/// `JSON` [int]
final integerTag = LocalTag.fromTagUri(_defaultYamlHandle, 'int');

/// `JSON` [double]
final floatTag = LocalTag.fromTagUri(_defaultYamlHandle, 'float');

//
// ** Dart Tags **
//

/// [Uri] tag
final uriTag = LocalTag.fromTagUri(_defaultYamlHandle, 'uri');

/// Any [LocalTag] that resolves to a [Scalar]
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
bool isYamlTag(LocalTag tag) =>
    tag == mappingTag || tag == sequenceTag || scalarTags.contains(tag);
