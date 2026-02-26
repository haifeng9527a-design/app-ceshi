// 测试 Polygon 领涨接口：dart run scripts/test_polygon_gainers.dart（在 app 目录下）
import 'dart:convert';
import 'dart:io';

void main() async {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('未找到 .env，请在 app 目录下执行');
    exit(1);
  }
  String? key;
  for (final line in envFile.readAsLinesSync()) {
    if (line.startsWith('POLYGON_API_KEY=')) {
      key = line.substring('POLYGON_API_KEY='.length).trim();
      break;
    }
  }
  if (key == null || key.isEmpty) {
    print('POLYGON_API_KEY 未配置');
    exit(1);
  }

  final uri = Uri.parse(
    'https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/gainers'
  ).replace(queryParameters: {'apiKey': key});

  print('请求: GET $uri');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    print('状态码: ${resp.statusCode}');
    if (resp.statusCode != 200) {
      print('响应: $body');
      exit(1);
    }
    final map = jsonDecode(body) as Map<String, dynamic>?;
    if (map == null) {
      print('响应非 JSON');
      exit(1);
    }
    final tickers = map['tickers'];
    if (tickers is List) {
      print('tickers 数量: ${tickers.length}');
      if (tickers.isNotEmpty) {
        final first = tickers.first;
        if (first is Map) {
          print('首条示例: ticker=${first['ticker']}, todaysChangePerc=${first['todaysChangePerc']}');
        }
      }
    } else {
      print('响应无 tickers 或格式异常: ${map.keys.toList()}');
    }
    print('完整 keys: ${map.keys.toList()}');
    if (map.containsKey('status')) print('status: ${map['status']}');
    if (map.containsKey('results')) print('results: ${map['results']}');
    if (body.length < 800) print('body: $body');
  } finally {
    client.close();
  }
}
