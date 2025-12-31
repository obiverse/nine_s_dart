/// 9S Networking - dial/listen for Remote Namespaces
///
/// "The network disappears. Machines become directories."
///
/// ## The Three Forms
///
/// | Form | Essence | File |
/// |------|---------|------|
/// | **Address** | Where to connect | address.dart |
/// | **Protocol** | How to encode messages | protocol.dart |
/// | **Transport** | Through what channel | transport.dart |
///
/// ## Usage
///
/// ```dart
/// import 'package:nine_s/nine_s.dart';
///
/// void main() async {
///   // Initialize TCP transport (once, on startup)
///   initNetworking();
///
///   // Client: Connect to remote namespace
///   final remote = await dial('tcp://192.168.1.100:9564');
///   final balance = await remote.read('/wallet/balance');
///   print(balance.value?.data);
///
///   // Server: Export local namespace
///   final kernel = Kernel()
///     ..mount('/wallet', walletNs)
///     ..mount('/vault', vaultNs);
///
///   final server = await listen('tcp://0.0.0.0:9564', kernel);
///   // Clients can now access /wallet/* and /vault/*
///
///   await server.close();
///   await remote.close();
/// }
/// ```
///
/// ## Philosophy
///
/// dial() and listen() are not operations - they are constructors.
/// They return Namespace instances that happen to talk over network.
/// The five frozen operations (read, write, list, watch, close) remain unchanged.
library;

import '../namespace/namespace.dart';
import 'address.dart';
import 'namespace.dart';
import 'protocol.dart';
import 'server.dart';
import 'transport.dart';
import 'transports/memory.dart';
import 'transports/tcp.dart';
import 'transports/unix.dart';
import 'transports/websocket.dart';

// Re-export public types
export 'address.dart' show Address, Schemes, defaultPort;
export 'namespace.dart' show AsyncNamespace, NetworkNamespace;
export 'protocol.dart'
    show Protocol, JsonLineProtocol, Request, Response, Op;
export 'server.dart' show Server;
export 'transport.dart' show Transport, Connection, Listener, Transports;

// Re-export transports for direct access if needed
export 'transports/memory.dart' show MemoryTransport;
export 'transports/tcp.dart' show TcpTransport;
export 'transports/unix.dart' show UnixTransport;
export 'transports/websocket.dart' show WebSocketTransport;

/// Initialize networking with all built-in transports
///
/// Call once on startup to register:
/// - `tcp://` - TCP sockets (network)
/// - `unix://` - Unix domain sockets (local IPC)
/// - `memory://` - In-process (testing/composition)
/// - `ws://` / `wss://` - WebSockets (browser-compatible)
///
/// Additional transports can be registered via [Transports.register].
void initNetworking() {
  Transports.register(Schemes.tcp, const TcpTransport());
  Transports.register(Schemes.unix, const UnixTransport());
  Transports.register(Schemes.memory, const MemoryTransport());
  Transports.register(Schemes.ws, const WebSocketTransport());
  Transports.register(Schemes.wss, const WebSocketTransport());
}

/// Dial - Connect to a remote namespace
///
/// Returns an AsyncNamespace that proxies to the remote server.
/// The network disappears - you interact via read/write/list/watch/close.
///
/// ```dart
/// final ns = await dial('tcp://192.168.1.100:9564');
/// final scroll = await ns.read('/wallet/balance');
/// await ns.close();
/// ```
Future<AsyncNamespace> dial(
  String address, {
  Protocol protocol = const JsonLineProtocol(),
}) async {
  final addr = Address.parse(address);
  final transport = Transports.require(addr.scheme);
  final connection = await transport.dial(addr);
  return NetworkNamespace(connection, protocol);
}

/// Listen - Export a namespace over network
///
/// Starts a server that accepts connections and serves the namespace.
/// Clients see the same paths as local code.
///
/// ```dart
/// final kernel = Kernel()
///   ..mount('/wallet', walletNs);
///
/// final server = await listen('tcp://0.0.0.0:9564', kernel);
/// // Clients can now dial and access /wallet/*
///
/// await server.close();
/// ```
Future<Server> listen(
  String address,
  Namespace namespace, {
  Protocol protocol = const JsonLineProtocol(),
}) async {
  final addr = Address.parse(address);
  final transport = Transports.require(addr.scheme);
  final listener = await transport.listen(addr);
  return Server.start(listener, namespace, protocol: protocol);
}
