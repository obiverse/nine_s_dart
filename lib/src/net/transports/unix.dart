/// Unix Transport - Local IPC via Unix Domain Sockets
///
/// Fast, secure communication between processes on the same host.
/// No network stack overhead - kernel-level IPC.
///
/// ## Usage
///
/// ```dart
/// Transports.register('unix', UnixTransport());
///
/// // Server
/// final server = await listen('unix:///tmp/9s.sock', kernel);
///
/// // Client
/// final ns = await dial('unix:///tmp/9s.sock');
/// ```
///
/// ## Philosophy
///
/// Unix sockets are the bridge between process isolation and shared resources.
/// A 9S server listening on a Unix socket becomes a local service,
/// accessible to any process with file permissions.
///
/// ## Platform Note
///
/// Unix sockets are not available on Windows (use named pipes instead).
/// This transport works on macOS, Linux, and other Unix-like systems.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../address.dart';
import '../transport.dart';

/// Unix Transport - Unix domain socket implementation
class UnixTransport implements Transport {
  const UnixTransport();

  @override
  Future<Connection> dial(Address addr) async {
    if (addr.scheme != Schemes.unix) {
      throw ArgumentError('UnixTransport only handles unix:// addresses');
    }

    final path = addr.path;
    if (path == null || path.isEmpty) {
      throw ArgumentError('Unix address requires a path');
    }

    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0, // Port ignored for Unix sockets
    );

    return UnixConnection(socket, addr);
  }

  @override
  Future<Listener> listen(Address addr) async {
    if (addr.scheme != Schemes.unix) {
      throw ArgumentError('UnixTransport only handles unix:// addresses');
    }

    final path = addr.path;
    if (path == null || path.isEmpty) {
      throw ArgumentError('Unix address requires a path');
    }

    // Remove existing socket file if present
    final socketFile = File(path);
    if (socketFile.existsSync()) {
      socketFile.deleteSync();
    }

    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0, // Port ignored for Unix sockets
    );

    return UnixListener(server, addr, path);
  }
}

/// Unix Connection - wraps a Socket connected via Unix domain socket
class UnixConnection implements Connection {
  final Socket _socket;
  final Address _remoteAddress;
  final StreamController<Uint8List> _incoming = StreamController();
  bool _isOpen = true;

  UnixConnection(this._socket, this._remoteAddress) {
    _socket.listen(
      (data) {
        if (_isOpen && !_incoming.isClosed) {
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
    _socket.add(data);
    await _socket.flush();
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

/// Unix Listener - wraps a ServerSocket bound to a Unix domain socket
class UnixListener implements Listener {
  final ServerSocket _server;
  final Address _address;
  final String _path;
  final StreamController<Connection> _connections = StreamController();

  UnixListener(this._server, this._address, this._path) {
    _server.listen(
      (socket) {
        final conn = UnixConnection(socket, _address);
        if (!_connections.isClosed) {
          _connections.add(conn);
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
    await _server.close();
    if (!_connections.isClosed) {
      await _connections.close();
    }

    // Clean up socket file
    final socketFile = File(_path);
    if (socketFile.existsSync()) {
      socketFile.deleteSync();
    }
  }

  @override
  Address get address => _address;
}
