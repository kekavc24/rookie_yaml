import 'dart:async';

import 'package:checks/checks.dart';
import 'package:dump_yaml/dump_yaml.dart';
import 'package:test/test.dart';

void main() {
  test('Buffers content to a stream', () {
    final controller = StreamController<String>();

    final dumper = YamlDumper(
      config: Config.defaults(),
      buffer: (indent, step, lf) => YamlBuffer.toStream(
        controller,
        indent: indent,
        step: step,
        lineEnding: lf,
      ),
    );

    dumper.dump([
      'Hello',
      'World',
      'from',
      {'my': 'stream'},
    ]);

    final stream = controller.stream;
    controller.close();

    check(stream.join()).completes(
      (str) => str.equals('''
- Hello
- World
- from
- my: stream
'''),
    );
  });

  test('Buffers content to any writer', () {
    final writer = <String>[];

    final dumper = YamlDumper(
      config: Config.yaml(styling: TreeConfig.flow()),
      buffer: (indent, step, lf) => YamlBuffer.ofWriter(
        writer.add,
        indent: indent,
        step: step,
        lineEnding: lf,
      ),
    );

    final mapSame = {'this': 'will', 'an': 'inline', 'flow': 'map'};

    dumper.dump(mapSame);
    check(writer.join()).equals(mapSame.toString());
  });
}
