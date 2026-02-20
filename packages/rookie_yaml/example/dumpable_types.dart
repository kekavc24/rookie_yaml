import 'package:rookie_yaml/rookie_yaml.dart';

void main(List<String> args) {
  // Scalars
  print(
    dumpObject(
      dumpableType(24)
        ..anchor = 'scalar'
        ..withNodeTag(localTag: TagShorthand.primary('tag')),
      dumper: ObjectDumper.compact(),
    ),
  );

  // Block sequence
  print(
    dumpObject(
      dumpableType([12, 12, 19, 63, 24])
        ..anchor = 'sequence'
        ..withNodeTag(localTag: sequenceTag),
      dumper: ObjectDumper.compact(),
    ),
  );

  final flowSequence = dumpableType(['in', '24', 'hours'])
    ..withVerbatimTag(
      VerbatimTag.fromTagShorthand(
        TagShorthand.primary('sequence'),
      ),
    );

  print(
    dumpObject(
      dumpableType({'gone': flowSequence})
        ..anchor = 'map'
        ..withNodeTag(localTag: mappingTag),
      dumper: ObjectDumper.of(
        mapStyle: NodeStyle.flow,
        iterableStyle: NodeStyle.flow,
        forceIterablesInline: true,
        forceMapsInline: true,
      ),
    ),
  );

  final verboseList = dumpableType([
    12,
    dumpableType(24)
      ..anchor = 'int'
      ..withNodeTag(localTag: integerTag),

    Alias('int'),
  ]);

  print(
    dumpObject(
      [
        // Override its node style.
        verboseList
          ..anchor = 'list'
          ..nodeStyle = NodeStyle.flow,

        Alias('list'),
      ],
      dumper: ObjectDumper.of(
        iterableStyle: NodeStyle.block,
        forceIterablesInline: true,
        unpackAliases: true,
      ),
    ),
  );
}
