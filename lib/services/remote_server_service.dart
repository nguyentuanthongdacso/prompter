import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/prompter_settings.dart';

class _NetworkInfoHelper {
  /// Returns all non-loopback IPv4 addresses grouped by interface name
  static Future<List<MapEntry<String, String>>> getAllIPs() async {
    final results = <MapEntry<String, String>>[];
    try {
      for (var interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            results.add(MapEntry(interface.name, addr.address));
          }
        }
      }
    } catch (_) {}
    return results;
  }

  /// Returns the most likely Wi-Fi IP address
  static Future<String?> getWifiIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      
      // Priority order: wlan > wi-fi > ap > en > eth > any
      // On Android, Wi-Fi is typically 'wlan0'
      // On iOS, Wi-Fi is typically 'en0'
      // On Windows, it varies but often contains 'Wi-Fi' or 'Wireless'
      final priorityPatterns = [
        RegExp(r'wlan', caseSensitive: false),
        RegExp(r'wi-?fi', caseSensitive: false),
        RegExp(r'wireless', caseSensitive: false),
        RegExp(r'^en\d', caseSensitive: false),
        RegExp(r'^ap', caseSensitive: false),
      ];

      for (final pattern in priorityPatterns) {
        for (var interface in interfaces) {
          if (pattern.hasMatch(interface.name)) {
            for (var addr in interface.addresses) {
              if (!addr.isLoopback) {
                return addr.address;
              }
            }
          }
        }
      }

      // Fallback: first non-loopback address
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

class RemoteServerService extends ChangeNotifier {
  HttpServer? _server;
  final Set<WebSocketChannel> _clients = {};
  final PrompterSettings _settings;
  bool _isRunning = false;
  int _port = 8080;
  String? _localIp;
  String? _webHtml;
  bool _suppressBroadcast = false;
  set suppressBroadcast(bool v) => _suppressBroadcast = v;

  // The latest text from the web remote UI (independent from app text)
  String _remoteText = '';
  String get remoteText => _remoteText;

  // Track current display state for newly connecting clients
  String _displayMode = '';
  bool _displayActive = false;

  // Last known scroll progress (0.0–1.0) for resuming across mode switches
  double _lastScrollProgress = 0.0;
  double get lastScrollProgress => _lastScrollProgress;

  // Stream for UI-level commands (e.g. start_fullscreen, start_overlay)
  final _commandController = StreamController<String>.broadcast();
  Stream<String> get commandStream => _commandController.stream;

  RemoteServerService(this._settings) {
    _settings.addListener(_onSettingsChanged);
  }

  List<MapEntry<String, String>> _allIps = [];

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get localIp => _localIp;
  int get clientCount => _clients.length;
  String get connectionUrl => 'http://$_localIp:$_port';
  List<MapEntry<String, String>> get allIps => _allIps;

  Future<void> startServer({int port = 8080}) async {
    if (_isRunning) return;

    _allIps = await _NetworkInfoHelper.getAllIPs();
    _localIp = await _getLocalIpAddress();

    // Pre-load web UI from assets
    try {
      _webHtml = await rootBundle.loadString('assets/web/index.html');
    } catch (e) {
      debugPrint('Failed to load web UI: $e');
      return;
    }

    // WebSocket handler
    final wsHandler = webSocketHandler((WebSocketChannel ws) {
      _clients.add(ws);
      notifyListeners();

      // Send full state on connect
      _sendTo(ws, {
        'type': 'full_sync',
        'data': _settings.toJson(),
      });

      // Send current display state if active
      if (_displayActive) {
        _sendTo(ws, {
          'type': 'display_state',
          'data': {
            'mode': _displayMode,
            'isActive': true,
          },
        });
      }

      // Send status
      _broadcastStatus();

      // Listen for messages
      ws.stream.listen(
        (message) {
          if (message is String) {
            _handleMessage(message, ws);
          }
        },
        onDone: () {
          _clients.remove(ws);
          notifyListeners();
          _broadcastStatus();
        },
        onError: (_) {
          _clients.remove(ws);
          notifyListeners();
        },
      );
    });

    // HTTP handler
    shelf.Response staticHandler(shelf.Request request) {
      final path = request.url.path;

      if (path.isEmpty || path == '/' || path == 'index.html') {
        return shelf.Response.ok(
          _webHtml!,
          headers: {'Content-Type': 'text/html; charset=utf-8'},
        );
      }

      // API: get settings as JSON
      if (path == 'api/settings') {
        return shelf.Response.ok(
          jsonEncode(_settings.toJson()),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      return shelf.Response.notFound('Not found');
    }

    // Combined handler: route /ws to WebSocket, rest to static
    FutureOr<shelf.Response> handler(shelf.Request request) {
      if (request.url.path == 'ws') {
        return wsHandler(request);
      }
      return staticHandler(request);
    }

    // Try binding to the requested port, fall back to next available
    for (var tryPort = port; tryPort < port + 10; tryPort++) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          tryPort,
        );
        _port = tryPort;
        _isRunning = true;
        notifyListeners();
        debugPrint('Remote control server running at http://$_localIp:$_port');
        return;
      } on SocketException catch (e) {
        debugPrint('Port $tryPort busy: $e');
        continue;
      }
    }

    debugPrint('Failed to start server: all ports busy');
  }

  Future<void> stopServer() async {
    for (final client in _clients.toList()) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    _isRunning = false;
    notifyListeners();
  }

  void _onSettingsChanged() {
    if (!_isRunning || _suppressBroadcast) return;
    _broadcast({
      'type': 'state_update',
      'data': _settings.toJson(),
    });
  }

  void _broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final client in _clients.toList()) {
      try {
        client.sink.add(encoded);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  void _sendTo(WebSocketChannel ws, Map<String, dynamic> message) {
    try {
      ws.sink.add(jsonEncode(message));
    } catch (_) {
      _clients.remove(ws);
    }
  }

  void _broadcastStatus() {
    _broadcast({
      'type': 'status',
      'data': {
        'connectedClients': _clients.length,
      },
    });
  }

  void _handleMessage(String raw, WebSocketChannel sender) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // Ignore malformed messages
    }

    final type = msg['type'] as String?;

    // Suppress broadcast while applying remote changes to avoid echo loop
    _suppressBroadcast = true;

    try {
      switch (type) {
        case 'update_settings':
          final data = msg['data'];
          if (data is Map<String, dynamic>) {
            _settings.applyFromJson(data);
          }
          break;
        case 'update_text':
          final data = msg['data'];
          if (data is Map<String, dynamic>) {
            final text = data['text'];
            if (text is String && text.length <= 100000) {
              _remoteText = text;
              _commandController.add('apply_text');
            }
          }
          return; // Don't broadcast — web text is independent from app text
        case 'command':
          final action = msg['action'] as String?;
          if (action != null) _handleCommand(action);
          break;
        case 'request_sync':
          _sendTo(sender, {
            'type': 'full_sync',
            'data': _settings.toJson(),
          });
          return; // Don't broadcast for sync requests
      }
    } finally {
      _suppressBroadcast = false;
    }

    // Broadcast updated state to ALL clients (including sender, for confirmation)
    _broadcast({
      'type': 'state_update',
      'data': _settings.toJson(),
    });
  }

  void _handleCommand(String action) {
    switch (action) {
      case 'play':
        _settings.setPlaying(true);
        _commandController.add(action);
        break;
      case 'pause':
        _settings.setPlaying(false);
        _commandController.add(action);
        break;
      case 'toggle':
        _settings.togglePlaying();
        _commandController.add(action);
        break;
      case 'speed_up':
        _settings.setScrollSpeed(_settings.scrollSpeed + 10);
        break;
      case 'speed_down':
        _settings.setScrollSpeed(_settings.scrollSpeed - 10);
        break;
      case 'start_fullscreen':
      case 'start_overlay':
      case 'stop_display':
      case 'reset':
      case 'rewind':
      case 'forward':
        _commandController.add(action);
        break;
    }
  }

  /// Broadcast scroll progress (0.0–1.0) to all connected web clients.
  /// Called from PrompterScreen / HomeScreen at ~10 Hz.
  void broadcastScrollProgress(double progress, {String mode = 'fullscreen'}) {
    _lastScrollProgress = progress.clamp(0.0, 1.0);
    if (!_isRunning || _clients.isEmpty) return;
    _broadcast({
      'type': 'scroll_progress',
      'data': {
        'progress': _lastScrollProgress,
        'mode': mode,
      },
    });
  }

  /// Broadcast display state (active/inactive, mode) to web clients.
  void broadcastDisplayState({required String mode, required bool isActive}) {
    _displayMode = mode;
    _displayActive = isActive;
    if (!_isRunning || _clients.isEmpty) return;
    _broadcast({
      'type': 'display_state',
      'data': {
        'mode': mode,
        'isActive': isActive,
      },
    });
  }

  Future<String?> _getLocalIpAddress() async {
    return await _NetworkInfoHelper.getWifiIP() ?? '0.0.0.0';
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _commandController.close();
    stopServer();
    super.dispose();
  }
}
