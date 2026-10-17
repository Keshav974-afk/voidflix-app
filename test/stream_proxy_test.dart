import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowflix_app/core/services/stream_proxy_service.dart';
import 'package:http/http.dart' as http;

class _RealNetworkHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = _RealNetworkHttpOverrides();

  test('StreamProxyService starts and rewrites HLS playlist', () async {
    // 1. Create a dummy upstream HTTP server simulating CDN
    final upstreamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamPort = upstreamServer.port;

    bool refererReceived = false;

    upstreamServer.listen((req) {
      if (req.uri.path == '/manifest.m3u8') {
        if (req.headers.value('referer') == 'https://vidlink.pro/') {
          refererReceived = true;
        }
        req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        req.response.write(
          '#EXTM3U\n'
          '#EXT-X-VERSION:3\n'
          '#EXT-X-TARGETDURATION:6\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="enc.key"\n'
          '#EXTINF:6.000,\n'
          'segment_0.ts\n'
          '#EXTINF:6.000,\n'
          'http://127.0.0.1:$upstreamPort/segment_1.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        req.response.close();
      } else if (req.uri.path.endsWith('.ts') || req.uri.path.endsWith('.key')) {
        req.response.headers.contentType = ContentType('video', 'MP2T');
        req.response.add([1, 2, 3, 4, 5]);
        req.response.close();
      } else {
        req.response.statusCode = 404;
        req.response.close();
      }
    });

    final upstreamUrl = 'http://127.0.0.1:$upstreamPort/manifest.m3u8';
    final proxy = StreamProxyService.instance;
    final proxyUrl = await proxy.getProxyUrl(upstreamUrl, {
      'Referer': 'https://vidlink.pro/',
      'User-Agent': 'Mozilla/5.0 Test',
    });

    expect(proxyUrl.contains('127.0.0.1'), isTrue);
    expect(proxyUrl.contains('stream.m3u8'), isTrue);

    // Fetch the proxied playlist
    final res = await http.get(Uri.parse(proxyUrl));
    expect(res.statusCode, equals(200));
    expect(res.body.contains('#EXTM3U'), isTrue);
    expect(refererReceived, isTrue);

    // Verify rewritten segments
    expect(res.body.contains('/segment.ts?sid='), isTrue);
    expect(res.body.contains('/proxy_resource.key?sid='), isTrue);

    // Extract one segment URL and fetch it via proxy
    final match = RegExp(r'/segment\.ts\?sid=[^\s]+').firstMatch(res.body);
    expect(match, isNotNull);
    final segmentPath = match!.group(0)!;
    final fullSegmentUrl = 'http://127.0.0.1:${proxy.port}$segmentPath';

    final segRes = await http.get(Uri.parse(fullSegmentUrl));
    expect(segRes.statusCode, equals(200));
    expect(segRes.bodyBytes, equals([1, 2, 3, 4, 5]));

    await upstreamServer.close(force: true);
    await proxy.stop();
  });
}
