/// Server - Export a Namespace over Network
///
/// The server-side counterpart to NetworkNamespace.
/// Accepts connections and serves a Namespace to clients.
///
/// ## Usage
///
/// ```dart
/// final kernel = Kernel()
///   ..mount('/wallet', walletNs)
///   ..mount('/vault', vaultNs);
///
/// final server = await listen('tcp://0.0.0.0:9564', kernel);
/// // Now clients can dial and access /wallet/*, /vault/*
///
/// await server.close();  // Stop accepting
/// ```
library;

import 'dart:async';
import 'dart:typed_data';

import '../namespace/namespace.dart';
import '../scroll/scroll.dart';
import 'address.dart';
import 'protocol.dart';
import 'transport.dart';

/// Server - Serves a Namespace over network
///
/// Each client connection gets a ServerSession that handles requests.
class Server {
  final Listener _listener;
  final Namespace _namespace;
  final Protocol _protocol;

  /// Active sessions
  final List<ServerSession> _sessions = [];

  /// Subscription to incoming connections
  StreamSubscription<Connection>? _subscription;

  /// Whether closed
  bool _closed = false;

  Server._(this._listener, this._namespace, this._protocol) {
    _subscription = _listener.connections.listen(
      _onConnection,
      onError: _onError,
    );
  }

  /// Create and start a server
  static Future<Server> start(
    Listener listener,
    Namespace namespace, {
    Protocol protocol = const JsonLineProtocol(),
  }) async {
    return Server._(listener, namespace, protocol);
  }

  /// Handle new connection
  void _onConnection(Connection conn) {
    if (_closed) {
      conn.close();
      return;
    }

    final session = ServerSession(conn, _namespace, _protocol);
    _sessions.add(session);

    // Remove session when it closes
    session._onClose = () {
      _sessions.remove(session);
    };
  }

  /// Handle listener error
  void _onError(Object error) {
    // Log and continue - don't crash the server
    // ignore: avoid_print
    print('Server: Listener error: $error');
  }

  /// Close the server
  ///
  /// Stops accepting new connections.
  /// Optionally closes existing sessions.
  Future<void> close({bool closeSessions = true}) async {
    _closed = true;
    await _subscription?.cancel();
    await _listener.close();

    if (closeSessions) {
      for (final session in _sessions.toList()) {
        await session.close();
      }
    }
    _sessions.clear();
  }

  /// Number of active sessions
  int get sessionCount => _sessions.length;

  /// Address we're listening on
  Address get address => _listener.address;
}

/// ServerSession - Handles one client connection
///
/// Receives requests, executes against Namespace, sends responses.
/// Manages watch subscriptions for this client.
class ServerSession {
  final Connection _connection;
  final Namespace _namespace;
  final Protocol _protocol;

  /// Active watch subscriptions by tag
  final Map<int, StreamSubscription<Scroll>> _watches = {};

  /// Incoming buffer
  Uint8List _buffer = Uint8List(0);

  /// Whether closed
  bool _closed = false;

  /// Callback when session closes
  void Function()? _onClose;

  /// Subscription to incoming data
  StreamSubscription<Uint8List>? _subscription;

  ServerSession(this._connection, this._namespace, this._protocol) {
    _subscription = _connection.incoming.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Process incoming data
  void _onData(Uint8List data) {
    // Append to buffer
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setAll(0, _buffer);
    newBuffer.setAll(_buffer.length, data);
    _buffer = newBuffer;

    // Split into complete messages
    final (messages, remaining) = JsonLineProtocol.splitMessages(_buffer);
    _buffer = remaining;

    // Process each message
    for (final msgBytes in messages) {
      try {
        final request = _protocol.decodeRequest(msgBytes);
        _handleRequest(request);
      } catch (e) {
        // Protocol error - log and continue
        // ignore: avoid_print
        print('ServerSession: Failed to decode request: $e');
      }
    }
  }

  /// Handle a request
  void _handleRequest(Request request) {
    switch (request.op) {
      case Op.read:
        _handleRead(request);
      case Op.write:
        _handleWrite(request);
      case Op.list:
        _handleList(request);
      case Op.watch:
        _handleWatch(request);
      case Op.unwatch:
        _handleUnwatch(request);
      case Op.close:
        _handleClose(request);
    }
  }

  /// Handle read request
  void _handleRead(Request req) {
    final result = _namespace.read(req.path);
    final response = switch (result) {
      Ok(:final value) => Response.ok(req.tag, scroll: value),
      Err(:final error) => Response.err(req.tag, error.message, _errorCode(error)),
    };
    _send(response);
  }

  /// Handle write request
  void _handleWrite(Request req) {
    final result = _namespace.write(req.path, req.data ?? {});
    final response = switch (result) {
      Ok(:final value) => Response.ok(req.tag, scroll: value),
      Err(:final error) => Response.err(req.tag, error.message, _errorCode(error)),
    };
    _send(response);
  }

  /// Handle list request
  void _handleList(Request req) {
    final result = _namespace.list(req.path);
    final response = switch (result) {
      Ok(:final value) => Response.ok(req.tag, paths: value),
      Err(:final error) => Response.err(req.tag, error.message, _errorCode(error)),
    };
    _send(response);
  }

  /// Handle watch request
  void _handleWatch(Request req) {
    final result = _namespace.watch(req.path);

    switch (result) {
      case Ok(:final value):
        // Subscribe and forward events
        final subscription = value.listen(
          (scroll) {
            if (!_closed) {
              _send(Response.event(req.tag, scroll));
            }
          },
          onError: (e) {
            if (!_closed) {
              final msg = e is NineError ? e.message : e.toString();
              _send(Response.err(req.tag, msg));
            }
          },
        );
        _watches[req.tag] = subscription;
        _send(Response.ok(req.tag));

      case Err(:final error):
        _send(Response.err(req.tag, error.message, _errorCode(error)));
    }
  }

  /// Handle unwatch request
  void _handleUnwatch(Request req) {
    final subscription = _watches.remove(req.tag);
    subscription?.cancel();
    _send(Response.ok(req.tag));
  }

  /// Handle close request
  void _handleClose(Request req) {
    _send(Response.ok(req.tag));
    close();
  }

  /// Send a response
  void _send(Response response) {
    if (_closed) return;
    try {
      final bytes = _protocol.encodeResponse(response);
      _connection.send(bytes);
    } catch (e) {
      // Send failed - connection probably dead
    }
  }

  /// Handle connection error
  void _onError(Object error) {
    close();
  }

  /// Handle connection close
  void _onDone() {
    close();
  }

  /// Close the session
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    // Cancel all watches
    for (final subscription in _watches.values) {
      await subscription.cancel();
    }
    _watches.clear();

    // Cancel incoming subscription
    await _subscription?.cancel();

    // Close connection
    await _connection.close();

    // Notify server
    _onClose?.call();
  }

  /// Convert error to code
  String _errorCode(NineError error) {
    return switch (error) {
      NotFoundError() => 'not_found',
      InvalidPathError() => 'invalid_path',
      InvalidDataError() => 'invalid_data',
      PermissionError() => 'permission',
      ClosedError() => 'closed',
      TimeoutError() => 'timeout',
      ConnectionError() => 'connection',
      UnavailableError() => 'unavailable',
      InternalError() => 'internal',
    };
  }
}
