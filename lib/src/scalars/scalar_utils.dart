import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/yaml_parser.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/yaml_nodes/node.dart';

const _octalPrefix = '0o';

Scalar<dynamic> formatScalar(
  ScalarBuffer buffer, {
  required ScalarStyle scalarStyle,
  required Set<ResolvedTag> tags,
  required Tag Function(LocalTag tag) resolver,
  bool trim = false,
}) {
  var content = buffer.bufferedString();

  if (trim) {
    content = content.trim();
  }

  var normalized = content.toLowerCase();

  dynamic value;
  LocalTag? tag;

  // Just write as string if a line break was stored
  if (!buffer.hasLineBreaks) {
    if (_parseInt(
          normalized,
          content: content,
          scalarStyle: scalarStyle,
          tags: tags,
          resolver: resolver,
        )
        case IntScalar parsedInt) {
      return parsedInt;
    }

    if (_isNull(normalized)) {
      value = null;
      tag = nullTag;
    } else if (bool.tryParse(normalized) case bool boolean) {
      value = boolean;
      tag = booleanTag;
    } else if (double.tryParse(normalized) case double parsedFloat) {
      value = parsedFloat;
      tag = floatTag;
    }
  }

  tag ??= stringTag;
  _resolveAndPushTag(tag, resolver: resolver, tags: tags);

  return Scalar(
    value ?? content,
    content: content,
    scalarStyle: scalarStyle,
    tags: tags,
  );
}

void _resolveAndPushTag(
  LocalTag localTag, {
  required Tag Function(LocalTag tag) resolver,
  required Set<ResolvedTag> tags,
}) {
  var tagToPush = resolver(localTag);

  tagToPush = switch (tagToPush) {
    GlobalTag globalTag => ParsedTag(globalTag, localTag.content),
    LocalTag localTag => ParsedTag(localTag, ''),
    _ => tagToPush as ResolvedTag,
  };

  tags.add(tagToPush);
}

bool _isNull(String value) {
  return value.isEmpty || value == '~' || value == 'null';
}

IntScalar? _parseInt(
  String normalized, {
  required String content,
  required ScalarStyle scalarStyle,
  required Set<ResolvedTag> tags,
  required Tag Function(LocalTag tag) resolver,
}) {
  int? radix;

  if (normalized.startsWith(_octalPrefix)) {
    normalized = normalized.replaceFirst(_octalPrefix, '');
    radix = 8;
  }

  // Check other bases used by YAML only if null
  radix ??= normalized.startsWith('0x') ? 16 : 10;

  if (int.tryParse(normalized, radix: radix) case int parsedInt) {
    _resolveAndPushTag(integerTag, resolver: resolver, tags: tags);
    return IntScalar(
      parsedInt,
      radix: radix,
      content: content,
      scalarStyle: scalarStyle,
      tags: tags,
    );
  }
  return null;
}
