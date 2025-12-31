/// TCP Transport - 9S over TCP/IP
///
/// The reference transport for 9S networking.
/// Reliable, ordered, connection-oriented.
///
/// ## Usage
///
/// ```dart
/// // Register on startup
/// Transports.register('tcp', TcpTransport());
///
/// // Then dial/listen work automatically
/// final ns = await dial('tcp://192.168.1.100:9564');
/// ```
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../address.dart';
import '../transport.dart';

/// TCP Transport implementation
class TcpTransport implements Transport {
  const TcpTransport();

  @override
  Future<Connection> dial(Address addr) async {
    if (addr.scheme != Schemes.tcp) {
      throw ArgumentError('TcpTransport only handles tcp:// addresses');
    }

    final socket = await Socket.connect(addr.host, addr.port);
    return TcpConnection(socket, addr);
  }

  @override
  Future<Listener> listen(Address addr) async {
    if (addr.scheme != Schemes.tcp) {
      throw ArgumentError('TcpTransport only handles tcp:// addresses');
    }

    final server = await ServerSocket.bind(
      addr.host.isEmpty ? InternetAddress.anyIPv4 : addr.host,
      addr.port,
    );

    return TcpListener(server, addr);
  }
}

/// TCP Connection - wraps a Socket
class TcpConnection implements Connection {
  final Socket _socket;
  final Address _remoteAddress;
  final StreamController<Uint8List> _incoming = StreamController();
  bool _isOpen = true;

  TcpConnection(this._socket, this._remoteAddress) {
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

/// TCP Listener - wraps a ServerSocket
class TcpListener implements Listener {
  final ServerSocket _server;
  final Address _address;
  final StreamController<Connection> _connections = StreamController();

  TcpListener(this._server, this._address) {
    _server.listen(
      (socket) {
        final addr = Address.tcp(
          socket.remoteAddress.address,
          socket.remotePort,
        );
        final conn = TcpConnection(socket, addr);
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
  }

  @override
  Address get address => _address;
}
