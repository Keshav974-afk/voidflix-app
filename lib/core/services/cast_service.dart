import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'stream_proxy_service.dart';

enum CastPlaybackStatus {
  idle,
  connecting,
  playing,
  paused,
  stopped,
  error,
}

class CastDevice {
  final String id;
  final String friendlyName;
  final String manufacturer;
  final String modelName;
  final String locationUrl;
  final String controlUrl;
  final String? renderingControlUrl;
  final String host;
  final int port;

  const CastDevice({
    required this.id,
    required this.friendlyName,
    required this.manufacturer,
    required this.modelName,
    required this.locationUrl,
    required this.controlUrl,
    this.renderingControlUrl,
    required this.host,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CastDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class CastService extends ChangeNotifier {
  static final CastService _instance = CastService._internal();
  factory CastService() => _instance;
  CastService._internal();

  static const MethodChannel _platform = MethodChannel('org.voidflix/notifications');

  final List<CastDevice> _devices = [];
  List<CastDevice> get devices => List.unmodifiable(_devices);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  CastDevice? _connectedDevice;
  CastDevice? get connectedDevice => _connectedDevice;
  bool get isCasting => _connectedDevice != null && _status != CastPlaybackStatus.idle && _status != CastPlaybackStatus.stopped;

  CastPlaybackStatus _status = CastPlaybackStatus.idle;
  CastPlaybackStatus get status => _status;

  String _currentTitle = '';
  String get currentTitle => _currentTitle;

  String? _currentPosterUrl;
  String? get currentPosterUrl => _currentPosterUrl;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  int _volume = 50;
  int get volume => _volume;

  Timer? _positionPollTimer;
  RawDatagramSocket? _ssdpSocket;
  Timer? _scanTimer;

  // ═══════════════════════════════════════════════════════════════
  // DISCOVERY ENGINE (Universal DLNA / UPnP SSDP)
  // ═══════════════════════════════════════════════════════════════

  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    _isScanning = true;
    _devices.clear();
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        await _platform.invokeMethod('acquireMulticastLock');
      }

      _ssdpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true, reusePort: false);
      _ssdpSocket?.broadcastEnabled = true;
      _ssdpSocket?.multicastLoopback = false;

      final ssdpTarget = InternetAddress('239.255.255.250');
      const ssdpPort = 1900;

      final targets = [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
      ];

      for (final target in targets) {
        final searchMsg =
            'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 3\r\n'
            'ST: $target\r\n\r\n';
        _ssdpSocket?.send(utf8.encode(searchMsg), ssdpTarget, ssdpPort);
      }

      _ssdpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _ssdpSocket?.receive();
          if (datagram != null) {
            _handleSsdpResponse(datagram.data);
          }
        }
      });

      _scanTimer?.cancel();
      _scanTimer = Timer(timeout, () {
        stopDiscovery();
      });
    } catch (e) {
      debugPrint('[CastService] Discovery error: $e');
      stopDiscovery();
    }
  }

  void stopDiscovery() {
    _isScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    try {
      _ssdpSocket?.close();
      _ssdpSocket = null;
    } catch (_) {}

    if (Platform.isAndroid) {
      _platform.invokeMethod('releaseMulticastLock');
    }
    notifyListeners();
  }

  void _handleSsdpResponse(List<int> rawBytes) {
    try {
      final text = utf8.decode(rawBytes, allowMalformed: true);
      final lines = text.split('\r\n');
      String? location;
      String? usn;

      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.startsWith('location:')) {
          location = line.substring(9).trim();
        } else if (lower.startsWith('usn:')) {
          usn = line.substring(4).trim();
        }
      }

      if (location != null && location.isNotEmpty) {
        _fetchDeviceDescription(location, usn ?? location);
      }
    } catch (_) {}
  }

  final Set<String> _fetchedLocations = {};

  Future<void> _fetchDeviceDescription(String locationUrl, String rawId) async {
    if (_fetchedLocations.contains(locationUrl)) return;
    _fetchedLocations.add(locationUrl);

    try {
      final uri = Uri.parse(locationUrl);
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return;

      final xml = resp.body;

      final friendlyName = _extractXmlTag(xml, 'friendlyName');
      if (friendlyName == null || friendlyName.isEmpty) return;

      // Ensure it is a media renderer or has AVTransport service
      if (!xml.contains('urn:schemas-upnp-org:service:AVTransport:1') &&
          !xml.contains('MediaRenderer')) {
        return;
      }

      final manufacturer = _extractXmlTag(xml, 'manufacturer') ?? 'Smart TV';
      final modelName = _extractXmlTag(xml, 'modelName') ?? 'DLNA Renderer';

      // Extract AVTransport controlURL
      final avTransportControl = _extractControlUrl(xml, 'urn:schemas-upnp-org:service:AVTransport:1');
      if (avTransportControl == null) return;

      final fullControlUrl = _resolveUrl(uri, avTransportControl);
      final renderingControl = _extractControlUrl(xml, 'urn:schemas-upnp-org:service:RenderingControl:1');
      final fullRenderingControlUrl = renderingControl != null ? _resolveUrl(uri, renderingControl) : null;

      final device = CastDevice(
        id: rawId.isNotEmpty ? rawId : locationUrl,
        friendlyName: friendlyName,
        manufacturer: manufacturer,
        modelName: modelName,
        locationUrl: locationUrl,
        controlUrl: fullControlUrl,
        renderingControlUrl: fullRenderingControlUrl,
        host: uri.host,
        port: uri.port,
      );

      final existingIdx = _devices.indexWhere((d) => d.id == device.id || d.friendlyName == device.friendlyName);
      if (existingIdx == -1) {
        _devices.add(device);
        notifyListeners();
      }
    } catch (_) {}
  }

  String? _extractXmlTag(String xml, String tag) {
    final startTag = '<$tag>';
    final endTag = '</$tag>';
    final startIdx = xml.indexOf(startTag);
    if (startIdx == -1) return null;
    final endIdx = xml.indexOf(endTag, startIdx + startTag.length);
    if (endIdx == -1) return null;
    return xml.substring(startIdx + startTag.length, endIdx).trim();
  }

  String? _extractControlUrl(String xml, String serviceType) {
    final serviceIdx = xml.indexOf(serviceType);
    if (serviceIdx == -1) return null;
    final block = xml.substring(serviceIdx);
    return _extractXmlTag(block, 'controlURL');
  }

  String _resolveUrl(Uri baseUri, String relativeOrAbsolute) {
    if (relativeOrAbsolute.startsWith('http://') || relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }
    if (relativeOrAbsolute.startsWith('/')) {
      return '${baseUri.scheme}://${baseUri.host}:${baseUri.port}$relativeOrAbsolute';
    }
    return '${baseUri.scheme}://${baseUri.host}:${baseUri.port}/$relativeOrAbsolute';
  }

  // ═══════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL ENGINE (UPnP AVTransport & RenderingControl)
  // ═══════════════════════════════════════════════════════════════

  Future<bool> castMedia({
    required CastDevice device,
    required String videoUrl,
    required String title,
    String? posterUrl,
    Duration startPosition = Duration.zero,
    Map<String, String>? headers,
  }) async {
    _connectedDevice = device;
    _currentTitle = title;
    _currentPosterUrl = posterUrl;
    _status = CastPlaybackStatus.connecting;
    _position = startPosition;
    _duration = Duration.zero;
    notifyListeners();

    try {
      // If casting a protected stream, proxy through local LAN HTTP server to attach headers
      String targetStreamUrl = videoUrl;
      if (headers != null && headers.isNotEmpty) {
        try {
          targetStreamUrl = await StreamProxyService.instance.getLanProxyUrl(videoUrl, headers);
          debugPrint('[CastService] Proxied stream for DLNA Smart TV: $targetStreamUrl');
        } catch (e) {
          debugPrint('[CastService] LAN proxy fallback to direct URL: $e');
        }
      }

      // 1. Stop current playback if active
      await _sendSoapAction(
        device.controlUrl,
        'AVTransport:1',
        'Stop',
        '<InstanceID>0</InstanceID>',
      );

      // 2. Build DIDL-Lite metadata
      final didlMetadata = _buildDidlMetadata(title, targetStreamUrl, posterUrl);

      // 3. SetAVTransportURI
      final setUriArgs =
          '<InstanceID>0</InstanceID>'
          '<CurrentURI>${_escapeXml(targetStreamUrl)}</CurrentURI>'
          '<CurrentURIMetaData>${_escapeXml(didlMetadata)}</CurrentURIMetaData>';

      final setUriSuccess = await _sendSoapAction(
        device.controlUrl,
        'AVTransport:1',
        'SetAVTransportURI',
        setUriArgs,
      );

      if (!setUriSuccess) {
        _status = CastPlaybackStatus.error;
        notifyListeners();
        return false;
      }

      // 4. Play
      final playSuccess = await _sendSoapAction(
        device.controlUrl,
        'AVTransport:1',
        'Play',
        '<InstanceID>0</InstanceID><Speed>1</Speed>',
      );

      if (playSuccess) {
        _status = CastPlaybackStatus.playing;
        if (startPosition > Duration.zero) {
          await seekTo(startPosition);
        }
        _startPositionPolling();
        notifyListeners();
        return true;
      } else {
        _status = CastPlaybackStatus.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[CastService] Cast error: $e');
      _status = CastPlaybackStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_connectedDevice == null) return;
    if (_status == CastPlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_connectedDevice == null) return;
    final ok = await _sendSoapAction(
      _connectedDevice!.controlUrl,
      'AVTransport:1',
      'Play',
      '<InstanceID>0</InstanceID><Speed>1</Speed>',
    );
    if (ok) {
      _status = CastPlaybackStatus.playing;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_connectedDevice == null) return;
    final ok = await _sendSoapAction(
      _connectedDevice!.controlUrl,
      'AVTransport:1',
      'Pause',
      '<InstanceID>0</InstanceID>',
    );
    if (ok) {
      _status = CastPlaybackStatus.paused;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_connectedDevice == null) return;
    await _sendSoapAction(
      _connectedDevice!.controlUrl,
      'AVTransport:1',
      'Stop',
      '<InstanceID>0</InstanceID>',
    );
    _status = CastPlaybackStatus.stopped;
    _stopPositionPolling();
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await stop();
    }
    _connectedDevice = null;
    _status = CastPlaybackStatus.idle;
    _position = Duration.zero;
    _duration = Duration.zero;
    _stopPositionPolling();
    notifyListeners();
  }

  Future<void> seekRelative(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration ? _duration : target);
    await seekTo(clamped);
  }

  Future<void> seekTo(Duration target) async {
    if (_connectedDevice == null) return;
    _position = target;
    notifyListeners();

    final targetStr = _formatDurationSoap(target);
    await _sendSoapAction(
      _connectedDevice!.controlUrl,
      'AVTransport:1',
      'Seek',
      '<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>$targetStr</Target>',
    );
  }

  Future<void> setVolume(int vol) async {
    if (_connectedDevice == null || _connectedDevice!.renderingControlUrl == null) return;
    _volume = vol.clamp(0, 100);
    notifyListeners();

    await _sendSoapAction(
      _connectedDevice!.renderingControlUrl!,
      'RenderingControl:1',
      'SetVolume',
      '<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>$_volume</DesiredVolume>',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EXTERNAL PLAYER LAUNCHER (VLC / Web Video Caster / BubbleUPnP)
  // ═══════════════════════════════════════════════════════════════

  static Future<bool> launchExternalPlayer({
    required String videoUrl,
    String? title,
    Map<String, String>? headers,
  }) async {
    try {
      if (Platform.isAndroid) {
        final res = await _platform.invokeMethod('openExternalPlayer', {
          'videoUrl': videoUrl,
          'title': title ?? 'Voidflix Video',
          'headers': headers ?? {},
        });
        return res == true;
      } else if (Platform.isWindows) {
        final vlcPaths = [
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
        ];
        for (final vp in vlcPaths) {
          if (File(vp).existsSync()) {
            await Process.start(vp, [videoUrl]);
            return true;
          }
        }
        final mpvPaths = [
          r'C:\Program Files\mpv\mpv.exe',
          r'C:\mpv\mpv.exe',
        ];
        for (final mp in mpvPaths) {
          if (File(mp).existsSync()) {
            await Process.start(mp, [videoUrl]);
            return true;
          }
        }
        return await launchUrl(
          Uri.parse(videoUrl),
          mode: LaunchMode.externalApplication,
        );
      }
      return false;
    } catch (e) {
      debugPrint('[CastService] Error launching external player: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════

  void _startPositionPolling() {
    _stopPositionPolling();
    _positionPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollPosition());
  }

  void _stopPositionPolling() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  Future<void> _pollPosition() async {
    if (_connectedDevice == null || _status != CastPlaybackStatus.playing) return;

    try {
      final xml = await _sendSoapQuery(
        _connectedDevice!.controlUrl,
        'AVTransport:1',
        'GetPositionInfo',
        '<InstanceID>0</InstanceID>',
      );

      if (xml != null) {
        final relTimeStr = _extractXmlTag(xml, 'RelTime');
        final trackDurationStr = _extractXmlTag(xml, 'TrackDuration');

        if (relTimeStr != null && relTimeStr.isNotEmpty && relTimeStr != 'NOT_IMPLEMENTED') {
          final pos = _parseDuration(relTimeStr);
          if (pos != null) _position = pos;
        }

        if (trackDurationStr != null && trackDurationStr.isNotEmpty && trackDurationStr != 'NOT_IMPLEMENTED') {
          final dur = _parseDuration(trackDurationStr);
          if (dur != null && dur > Duration.zero) _duration = dur;
        }

        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> _sendSoapAction(String controlUrl, String serviceName, String action, String argsXml) async {
    final res = await _sendSoapQuery(controlUrl, serviceName, action, argsXml);
    return res != null && !res.contains('s:Fault') && !res.contains('UPnPError');
  }

  Future<String?> _sendSoapQuery(String controlUrl, String serviceName, String action, String argsXml) async {
    try {
      final soapBody =
          '<?xml version="1.0" encoding="utf-8"?>\r\n'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
          '<s:Body>'
          '<u:$action xmlns:u="urn:schemas-upnp-org:service:$serviceName">'
          '$argsXml'
          '</u:$action>'
          '</s:Body>'
          '</s:Envelope>';

      final headers = {
        'SOAPAction': '"urn:schemas-upnp-org:service:$serviceName#$action"',
        'Content-Type': 'text/xml; charset="utf-8"',
      };

      final resp = await http
          .post(Uri.parse(controlUrl), headers: headers, body: utf8.encode(soapBody))
          .timeout(const Duration(seconds: 4));

      return resp.body;
    } catch (_) {
      return null;
    }
  }

  String _buildDidlMetadata(String title, String url, String? posterUrl) {
    final mimeType = url.contains('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp4';
    final safeTitle = _escapeXml(title);
    final safeUrl = _escapeXml(url);
    final artXml = posterUrl != null && posterUrl.isNotEmpty
        ? '<upnp:albumArtURI xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">${_escapeXml(posterUrl)}</upnp:albumArtURI>'
        : '';

    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="1" parentID="0" restricted="1">'
        '<dc:title>$safeTitle</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '$artXml'
        '<res protocolInfo="http-get:*:$mimeType:*">$safeUrl</res>'
        '</item>'
        '</DIDL-Lite>';
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _formatDurationSoap(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Duration? _parseDuration(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 3) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final secondsPart = parts[2].split('.');
        final seconds = int.tryParse(secondsPart[0]) ?? 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds);
      }
    } catch (_) {}
    return null;
  }
}
