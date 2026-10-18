// C6 over a real pipe: the server starts as an MCP client would start it (its own process, another working directory, absolute config
// paths), and stdout carries nothing but JSON-RPC messages, one per line.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('initialize, tools/list and plan_route over stdio; stdout is protocol only', () async {
    final root = Directory.current.absolute.parent.parent.path;
    final proc = await Process.start(
      Platform.resolvedExecutable,
      ['run', '${Directory.current.absolute.path}${Platform.pathSeparator}bin${Platform.pathSeparator}mcp_stdio.dart'],
      workingDirectory: Directory.systemTemp.path,
      environment: {
        'CITY': 'chennai',
        'CITIES_CONFIG': '$root/config/cities.yaml',
        'HAZARD_CONFIG': '$root/config/hazard_classes.yaml',
        'EVENT_STATE': 'dry',
      },
    );
    final lines = proc.stdout.transform(utf8.decoder).transform(const LineSplitter());
    final replies = StreamIterator(lines);
    final stderrText = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(stderrText.write);
    Future<Map<String, Object?>> send(Map<String, Object?> m) async {
      proc.stdin.writeln(jsonEncode(m));
      await proc.stdin.flush();
      expect(await replies.moveNext().timeout(const Duration(minutes: 3)), isTrue, reason: '$stderrText');
      return (jsonDecode(replies.current) as Map).cast<String, Object?>();
    }

    try {
      final init = await send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18', 'capabilities': <String, Object?>{}, 'clientInfo': {'name': 't', 'version': '1'}},
      });
      expect((init['result']! as Map)['protocolVersion'], '2025-06-18');
      proc.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
      final list = await send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      expect(((list['result']! as Map)['tools']! as List), hasLength(4));
      final route = await send({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'plan_route',
          'arguments': {
            'from': {'lat': 13.0418, 'lon': 80.2341},
            'to': {'lat': 12.9791, 'lon': 80.2209},
          },
        },
      });
      final s = ((route['result']! as Map)['structuredContent']! as Map).cast<String, Object?>();
      expect(s['answer_verified'], isTrue);
      expect(s['traffic_signals'], greaterThan(0));
      // A malformed line gets a parse error, and the server keeps going.
      proc.stdin.writeln('{not json');
      expect(await replies.moveNext(), isTrue);
      expect(((jsonDecode(replies.current) as Map)['error']! as Map)['code'], -32700);
      final ping = await send({'jsonrpc': '2.0', 'id': 4, 'method': 'ping'});
      expect(ping['result'], <String, Object?>{});
      expect(stderrText.toString(), contains('ready'));
    } finally {
      await proc.stdin.close();
      proc.kill();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
