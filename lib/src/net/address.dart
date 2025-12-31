/// Address - The "Where" of Networking
///
/// Parses URI-style addresses into components.
/// Scheme determines transport, host:port determines location.
///
/// ## Examples
///
/// ```dart
/// final addr = Address.parse('tcp://192.168.1.100:9564');
/// print(addr.scheme);  // "tcp"
/// print(addr.host);    // "192.168.1.100"
/// print(addr.port);    // 9564
///
/// final unix = Address.parse('unix:///tmp/9s.sock');
/// print(unix.scheme);  // "unix"
/// print(unix.path);    // "/tmp/9s.sock"
/// ```
library;

/// Default port for 9S protocol (spells "9S64" on phone keypad)
const defaultPort = 9564;

/// Supported transport schemes
abstract final class Schemes {
  static const tcp = 'tcp';
  static const unix = 'unix';
  static const memory = 'memory';
  static const ws = 'ws';
  static const wss = 'wss';
  // Future: quic
}

/// Address - Parsed network location
///
/// Immutable value object representing where to connect.
class Address {
  /// Transport scheme (tcp, unix, memory, ws, etc.)
  final String scheme;

  /// Host name or IP address (for tcp/ws)
  final String host;

  /// Port number (for tcp/ws)
  final int port;

  /// Path (for unix sockets, or namespace path after connection)
  final String? path;

  const Address({
    required this.scheme,
    this.host = '',
    this.port = defaultPort,
    this.path,
  });

  /// Parse an address string
  ///
  /// Formats:
  /// - `tcp://host:port` - TCP connection
  /// - `tcp://host` - TCP with default port
  /// - `unix:///path/to/socket` - Unix domain socket
  /// - `memory://` - In-process (for testing)
  ///
  /// Throws [FormatException] on invalid input.
  factory Address.parse(String address) {
    final uri = Uri.tryParse(address);
    if (uri == null) {
      throw FormatException('Invalid address: $address');
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) {
      throw FormatException('Missing scheme in address: $address');
    }

    return switch (scheme) {
      Schemes.tcp => Address(
          scheme: scheme,
          host: uri.host.isEmpty ? 'localhost' : uri.host,
          port: uri.port == 0 ? defaultPort : uri.port,
          path: uri.path.isEmpty ? null : uri.path,
        ),
      Schemes.unix => Address(
          scheme: scheme,
          path: uri.path,
        ),
      Schemes.memory => const Address(scheme: Schemes.memory),
      _ => Address(
          scheme: scheme,
          host: uri.host,
          port: uri.port == 0 ? defaultPort : uri.port,
          path: uri.path.isEmpty ? null : uri.path,
        ),
    };
  }

  /// Create a TCP address
  factory Address.tcp(String host, [int port = defaultPort]) {
    return Address(scheme: Schemes.tcp, host: host, port: port);
  }

  /// Create a Unix socket address
  factory Address.unix(String path) {
    return Address(scheme: Schemes.unix, path: path);
  }

  /// Create a memory address (in-process)
  const factory Address.memory() = _MemoryAddress;

  /// Convert back to URI string
  @override
  String toString() {
    return switch (scheme) {
      Schemes.tcp => 'tcp://$host:$port${path ?? ""}',
      Schemes.unix => 'unix://$path',
      Schemes.memory => 'memory://',
      _ => '$scheme://$host${port != 0 ? ":$port" : ""}${path ?? ""}',
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Address) return false;
    return scheme == other.scheme &&
        host == other.host &&
        port == other.port &&
        path == other.path;
  }

  @override
  int get hashCode => Object.hash(scheme, host, port, path);
}

/// Memory address singleton
class _MemoryAddress extends Address {
  const _MemoryAddress() : super(scheme: Schemes.memory);
}
