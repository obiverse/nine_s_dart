/// Transport - The "Through What Channel" of Networking
///
/// Defines the abstract channel for communication.
/// TCP, Unix sockets, WebSockets are all Transports.
///
/// ## The Three Interfaces
///
/// - **Transport** - Factory for connections and listeners
/// - **Connection** - Bidirectional byte stream
/// - **Listener** - Accepts incoming connections
///
/// ## Philosophy
///
/// Transport is pure I/O - it knows nothing about 9S, Scrolls, or Protocol.
/// It just moves bytes. Protocol gives those bytes meaning.
/// This separation enables swapping transports without changing protocol logic.
library;

import 'dart:async';
import 'dart:typed_data';

import 'address.dart';

/// Transport - Factory for connections and listeners
///
/// Each scheme (tcp, unix, ws) has a Transport implementation.
abstract interface class Transport {
  /// Connect to a remote address
  ///
  /// Returns a Connection for bidirectional communication.
  Future<Connection> dial(Address addr);

  /// Listen for incoming connections
  ///
  /// Returns a Listener that yields connections.
  Future<Listener> listen(Address addr);
}

/// Connection - Bidirectional byte stream
///
/// Represents an established channel between two endpoints.
/// Send bytes out, receive bytes in.
abstract interface class Connection {
  /// Stream of incoming data chunks
  Stream<Uint8List> get incoming;

  /// Send data to the remote endpoint
  ///
  /// The future completes when data is sent (not necessarily received).
  Future<void> send(Uint8List data);

  /// Close the connection
  ///
  /// After close, send() throws and incoming completes.
  Future<void> close();

  /// Remote address (for logging/debugging)
  Address get remoteAddress;

  /// Whether connection is still open
  bool get isOpen;
}

/// Listener - Accepts incoming connections
///
/// Server-side endpoint that yields new connections.
abstract interface class Listener {
  /// Stream of incoming connections
  Stream<Connection> get connections;

  /// Stop accepting connections
  ///
  /// Existing connections are NOT closed.
  Future<void> close();

  /// Address we're listening on
  Address get address;
}

/// Transport registry
///
/// Maps schemes to transport implementations.
/// Allows extending with new transports at runtime.
class Transports {
  static final _transports = <String, Transport>{};

  /// Register a transport for a scheme
  static void register(String scheme, Transport transport) {
    _transports[scheme] = transport;
  }

  /// Get transport for a scheme
  ///
  /// Returns null if scheme is not registered.
  static Transport? get(String scheme) => _transports[scheme];

  /// Get transport or throw
  static Transport require(String scheme) {
    final transport = _transports[scheme];
    if (transport == null) {
      throw ArgumentError('No transport registered for scheme: $scheme');
    }
    return transport;
  }

  /// List registered schemes
  static Iterable<String> get schemes => _transports.keys;
}
