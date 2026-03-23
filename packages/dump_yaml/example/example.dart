import 'dart:async';

import 'package:dump_yaml/dump_yaml.dart';

void main(List<String> args) async {
  final someLazyStream = StreamController<String>();

  final dumper = YamlDumper(
    config: Config.defaults(),
    buffer: YamlBuffer.toStream(someLazyStream),
  );

  dumper.dump([
    'I',
    'love',
    {'streaming': 'things'},
    'lazily',
  ]);

  someLazyStream.close();
  final chunks = await someLazyStream.stream.toList();

  /*
   * Lazy chunks as the dumper walks the YAML representation tree for your
   * object.

[, -,  , I,
, , -,  , love,
, , -,  , streaming, :,  , things,
, , -,  , lazily,
]

*/
  print(chunks);

  /*
  - I
  - love
  - streaming: things
  - lazily
  */
  print(chunks.join());
}
