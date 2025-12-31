/// WebSocket Transport - Browser-Compatible Networking
///
/// Full-duplex communication that works in browsers.
/// The universal transport for web clients.
///
/// ## Usage
///
/// ```dart
/// Transports.register('ws', WebSocketTransport());
/// Transports.register('wss', WebSocketTransport());
///
/// // Server (dart:io)
/// final server = await listen('ws://0.0.0.0:9564', kernel);
///
/// // Client (works in browser too)
/// final ns = await dial('ws://example.com:9564');
/// // or secure:
/// final ns = await dial('wss://example.com:9564');
/// ```
///
/// ## Philosophy
///
/// WebSocket is HTTP's escape hatch to real networking.
/// It upgrades the request-response paradigm to bidirectional streams.
/// For 9S, it means the browser can be a full namespace client.
///
/// ## Notes
///
/// - Server uses dart:io (HttpServer + WebSocket.upgrade)
/// - Client uses dart:io WebSocket (for now; dart:html for browser)
/// - wss:// requires TLS configuration on server
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../address.dart';
import '../transport.dart';

/// WebSocket Transport - WebSocket implementation
class WebSocketTransport implements Transport {
  const WebSocketTransport();

  @override
  Future<Connection> dial(Address addr) async {
    if (addr.scheme != 'ws' && addr.scheme != 'wss') {
      throw ArgumentError('WebSocketTransport only handles ws:// or wss:// addresses');
    }

    final uri = Uri(
      scheme: addr.scheme,
      host: addr.host,
      port: addr.port,
      path: addr.path,
    );

    final socket = await WebSocket.connect(uri.toString());
    return WebSocketConnection(socket, addr);
  }

  @override
  Future<Listener> listen(Address addr) async {
    if (addr.scheme != 'ws' && addr.scheme != 'wss') {
      throw ArgumentError('WebSocketTransport only handles ws:// or wss:// addresses');
    }

    // For wss, caller should provide security context via custom setup
    final server = await HttpServer.bind(
      addr.host.isEmpty ? InternetAddress.anyIPv4 : addr.host,
      addr.port,
    );

    return WebSocketListener(server, addr);
  }
}

/// WebSocket Connection - wraps a WebSocket
class WebSocketConnection implements Connection {
  final WebSocket _socket;
  final Address _remoteAddress;
  final StreamController<Uint8List> _incoming = StreamController();
  bool _isOpen = true;

  WebSocketConnection(this._socket, this._remoteAddress) {
    _socket.listen(
      (data) {
        if (!_isOpen || _incoming.isClosed) return;

        // WebSocket can receive String or List<int>
        if (data is String) {
          _incoming.add(Uint8List.fromList(data.codeUnits));
        } else if (data is List<int>) {
          _incoming.add(Uint8List.fromList(data));
        }
      },
      onError: (e) {
        if (!_incoming.isClosed) {
          _incoming.addError(e);
        }
      },
      onDone: () {
        _isOpen = false;
        if (!_incoming.isClosed) {
          _incoming.close();
        }
      },
    );
  }

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) {
      throw StateError('Connection is closed');
    }
    // Send as binary
    _socket.add(data);
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    await _socket.close();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  @override
  Address get remoteAddress => _remoteAddress;

  @override
  bool get isOpen => _isOpen;
}

/// WebSocket Listener - wraps an HttpServer that upgrades to WebSocket
class WebSocketListener implements Listener {
  final HttpServer _server;
  final Address _address;
  final StreamController<Connection> _connections = StreamController();
  late final StreamSubscription<HttpRequest> _subscription;

  WebSocketListener(this._server, this._address) {
    _subscription = _server.listen(
      (request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            final remoteAddr = Address(
              scheme: _address.scheme,
              host: request.connectionInfo?.remoteAddress.address ?? 'unknown',
              port: request.connectionInfo?.remotePort ?? 0,
            );
            final conn = WebSocketConnection(socket, remoteAddr);
            if (!_connections.isClosed) {
              _connections.add(conn);
            }
          } catch (e) {
            // Failed to upgrade, reject
            request.response
              ..statusCode = HttpStatus.badRequest
              ..close();
          }
        } else {
          // Not a WebSocket upgrade request
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('WebSocket upgrade required')
            ..close();
        }
      },
      onError: (e) {
        if (!_connections.isClosed) {
          _connections.addError(e);
        }
      },
      onDone: () {
        if (!_connections.isClosed) {
          _connections.close();
        }
      },
    );
  }

  @override
  Stream<Connection> get connections => _connections.stream;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _server.close();
    if (!_connections.isClosed) {
      await _connections.close();
    }
  }

  @override
  Address get address => _address;
}
