/// Memory Transport - In-Process Communication
///
/// The essential transport for testing and composition.
/// No network, no I/O - just streams between isolates or same-process.
///
/// ## Usage
///
/// ```dart
/// Transports.register('memory', MemoryTransport());
///
/// // Create a listener
/// final listener = await transport.listen(Address.memory());
///
/// // Client dials the same listener
/// final client = await transport.dial(listener.address);
///
/// // Server accepts
/// final server = await listener.connections.first;
///
/// // Now client and server can communicate
/// ```
///
/// ## Philosophy
///
/// Memory transport is the identity function of transports.
/// It proves the abstraction works by being the simplest possible implementation.
/// If your protocol works over MemoryTransport, it works.
library;

import 'dart:async';
import 'dart:typed_data';

import '../address.dart';
import '../transport.dart';

/// Memory Transport - In-process bidirectional channels
class MemoryTransport implements Transport {
  const MemoryTransport();

  /// Active listeners by address ID
  static final _listeners = <int, MemoryListener>{};
  static int _nextId = 0;

  @override
  Future<Connection> dial(Address addr) async {
    if (addr.scheme != Schemes.memory) {
      throw ArgumentError('MemoryTransport only handles memory:// addresses');
    }

    // Find the listener for this address
    final listenerId = addr.port; // We use port as listener ID
    final listener = _listeners[listenerId];
    if (listener == null) {
      throw StateError('No listener at address: $addr');
    }

    // Create a bidirectional channel pair
    final (clientConn, serverConn) = _createChannelPair(addr);

    // Deliver server connection to listener
    listener._acceptConnection(serverConn);

    return clientConn;
  }

  @override
  Future<Listener> listen(Address addr) async {
    if (addr.scheme != Schemes.memory) {
      throw ArgumentError('MemoryTransport only handles memory:// addresses');
    }

    final id = _nextId++;
    final boundAddr = Address(scheme: Schemes.memory, port: id);
    final listener = MemoryListener(boundAddr, id);
    _listeners[id] = listener;

    return listener;
  }

  /// Create a connected pair of memory connections
  static (MemoryConnection, MemoryConnection) _createChannelPair(Address addr) {
    // Two stream controllers - one for each direction
    final clientToServer = StreamController<Uint8List>.broadcast();
    final serverToClient = StreamController<Uint8List>.broadcast();

    final clientConn = MemoryConnection(
      incoming: serverToClient.stream,
      outgoing: clientToServer,
      remoteAddr: addr,
    );

    final serverConn = MemoryConnection(
      incoming: clientToServer.stream,
      outgoing: serverToClient,
      remoteAddr: const Address(scheme: Schemes.memory, port: -1),
    );

    // Link close behavior
    clientConn._peer = serverConn;
    serverConn._peer = clientConn;

    return (clientConn, serverConn);
  }
}

/// Memory Connection - In-process stream pair
class MemoryConnection implements Connection {
  final Stream<Uint8List> _incoming;
  final StreamController<Uint8List> _outgoing;
  final Address _remoteAddress;
  bool _isOpen = true;
  MemoryConnection? _peer;

  MemoryConnection({
    required Stream<Uint8List> incoming,
    required StreamController<Uint8List> outgoing,
    required Address remoteAddr,
  })  : _incoming = incoming,
        _outgoing = outgoing,
        _remoteAddress = remoteAddr;

  @override
  Stream<Uint8List> get incoming => _incoming;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) {
      throw StateError('Connection is closed');
    }
    if (!_outgoing.isClosed) {
      _outgoing.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;

    if (!_outgoing.isClosed) {
      await _outgoing.close();
    }

    // Close peer's incoming stream
    _peer?._closeIncoming();
  }

  void _closeIncoming() {
    _isOpen = false;
  }

  @override
  Address get remoteAddress => _remoteAddress;

  @override
  bool get isOpen => _isOpen;
}

/// Memory Listener - Accepts in-process connections
class MemoryListener implements Listener {
  final Address _address;
  final int _id;
  final StreamController<Connection> _connections = StreamController();
  bool _closed = false;

  MemoryListener(this._address, this._id);

  void _acceptConnection(MemoryConnection conn) {
    if (!_closed && !_connections.isClosed) {
      _connections.add(conn);
    }
  }

  @override
  Stream<Connection> get connections => _connections.stream;

  @override
  Future<void> close() async {
    _closed = true;
    MemoryTransport._listeners.remove(_id);
    if (!_connections.isClosed) {
      await _connections.close();
    }
  }

  @override
  Address get address => _address;
}
