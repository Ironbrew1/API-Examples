import 'dart:convert';
import 'dart:io';

const baseUrl = 'https://ironbrew1.com';
const apiKey = 'IB1-APIKEYHERE';

const inputPath = 'input.lua';
const outputPath = 'output.lua';

const query = 'platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false';

const retryDelay = 5;
const maxWait = 240;
const maxFails = 3;

final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);

Never fail(String message) {
  stderr.writeln(message);
  exit(1);
}

Future<(int, List<int>)> send(String method, String path, [List<int>? body]) async {
  final request = await client.openUrl(method, Uri.parse(baseUrl + path));
  request.headers.set('Key', apiKey);
  if (body != null) {
    request.headers.contentType = ContentType.text;
    request.add(body);
  }
  final response = await request.close();
  final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
  return (response.statusCode, bytes);
}

Future<void> main() async {
  final (queueCode, queueBody) = await send('POST', '/obfuscate?$query', await File(inputPath).readAsBytes());
  if (queueCode ~/ 100 != 2) fail('Unable to queue obfuscation: $queueCode');

  final queued = jsonDecode(utf8.decode(queueBody));
  print('Obfuscation started with GUID: ${queued['uploadGuid']}');

  var elapsed = 0;
  var fails = 0;
  var wait = 0;

  while (true) {
    wait += retryDelay;
    await Future.delayed(Duration(seconds: wait));
    elapsed += wait;

    final (code, body) = await send('GET', queued['statusUrl']);
    if (code ~/ 100 != 2) {
      fails++;
      print('Status check failed with status: $code ($fails/$maxFails)');
      if (fails >= maxFails || elapsed >= maxWait) fail('Obfuscation failed (fails: $fails | elapsed time: $elapsed)');
      continue;
    }

    final status = jsonDecode(utf8.decode(body));

    if (status['status'] == 'completed') {
      print('Obfuscation completed in $elapsed seconds');
      final (downloadCode, script) = await send('GET', status['downloadUrl']);
      if (downloadCode ~/ 100 != 2) fail('Download failed with status: $downloadCode');
      await File(outputPath).writeAsBytes(script);
      print('Saved obfuscated script to $outputPath');
      break;
    }

    if (status['status'] == 'failed' || elapsed >= maxWait) {
      fail('Obfuscation failed (status: ${status['status']} | elapsed time: $elapsed)');
    }

    print('Obfuscation is still in progress. Elapsed time: $elapsed seconds. Checking again in ${retryDelay + wait} seconds.');
  }

  client.close();
}
