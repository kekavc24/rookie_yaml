import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

base class YamlParser {
  YamlParser({required String yaml}) : _scanner = ChunkScanner(source: yaml);

  final ChunkScanner _scanner;

  //Node parseYaml() {}
}
