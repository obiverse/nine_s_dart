/// NetworkNamespace - Remote Namespace over Transport + Protocol
///
/// Combines a Connection with a Protocol to create an AsyncNamespace.
/// This is the client-side proxy to a remote namespace.
///
/// ## How It Works
///
/// ```
/// Local Code → NetworkNamespace → Protocol → Connection → [Network] → Server
/// ```
///
/// 1. Call read('/path')
/// 2. Create Request{tag, op: read, path}
/// 3. Encode via Protocol
/// 4. Send via Connection
/// 5. Receive response bytes
/// 6. Decode via Protocol
/// 7. Return Result
///
/// Watch is special: server pushes events with `event: true`.
library;

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import '../namespace/namespace.dart';
import '../scroll/scroll.dart';
import 'protocol.dart';
import 'transport.dart';

/// NetworkNamespace - Async namespace over network
///
/// Implements AsyncNamespace by proxying to a remote server.
class NetworkNamespace implements AsyncNamespace {
  final Connection _connection;
  final Protocol _protocol;

  /// Pending requests awaiting response
  final Map<int, Completer<Response>> _pending = {};

  /// Active watch streams by tag
  final Map<int, StreamController<Scroll>> _watches = {};

  /// Tag counter for multiplexing
  int _nextTag = 1;

  /// Incoming message buffer (for partial messages)
  Uint8List _buffer = Uint8List(0);

  /// Whether closed
  bool _closed = false;

  /// Subscription to incoming data
  StreamSubscription<Uint8List>? _subscription;

  NetworkNamespace(this._connection, this._protocol) {
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
        final response = _protocol.decodeResponse(msgBytes);
        _handleResponse(response);
      } catch (e) {
        // Protocol error - log and continue
        // ignore: avoid_print
        print('NetworkNamespace: Failed to decode response: $e');
      }
    }
  }

  /// Handle a decoded response
  void _handleResponse(Response response) {
    if (response.event) {
      // Watch event - dispatch to stream
      final controller = _watches[response.tag];
      if (controller != null && response.scroll != null) {
        controller.add(response.scroll!);
      }
    } else {
      // Request response - complete the pending future
      final completer = _pending.remove(response.tag);
      if (completer != null) {
        completer.complete(response);
      }
    }
  }

  /// Handle connection error
  void _onError(Object error) {
    // Fail all pending requests
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();

    // Close all watches
    for (final controller in _watches.values) {
      controller.addError(error);
      controller.close();
    }
    _watches.clear();
  }

  /// Handle connection close
  void _onDone() {
    _closed = true;

    // Fail pending requests
    const error = ConnectionError('connection closed');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();

    // Close watches
    for (final controller in _watches.values) {
      controller.close();
    }
    _watches.clear();
  }

  /// Send a request and wait for response
  Future<Response> _request(Request req) async {
    if (_closed) {
      throw const ClosedError();
    }

    final completer = Completer<Response>();
    _pending[req.tag] = completer;

    try {
      final bytes = _protocol.encodeRequest(req);
      await _connection.send(bytes);
      return await completer.future;
    } catch (e) {
      _pending.remove(req.tag);
      rethrow;
    }
  }

  /// Get next tag
  int _tag() => _nextTag++;

  // ============================================================================
  // AsyncNamespace Implementation
  // ============================================================================

  @override
  Future<NineResult<Scroll?>> read(String path) async {
    try {
      final response = await _request(Request.read(_tag(), path));
      if (response.ok) {
        return Ok(response.scroll);
      } else {
        return Err(_errorFromResponse(response));
      }
    } catch (e) {
      return Err(_errorFromException(e));
    }
  }

  @override
  Future<NineResult<Scroll>> write(String path, Map<String, dynamic> data) async {
    try {
      final response = await _request(Request.write(_tag(), path, data));
      if (response.ok && response.scroll != null) {
        return Ok(response.scroll!);
      } else if (response.ok) {
        return const Err(InternalError('write response missing scroll'));
      } else {
        return Err(_errorFromResponse(response));
      }
    } catch (e) {
      return Err(_errorFromException(e));
    }
  }

  @override
  Future<NineResult<Scroll>> writeScroll(Scroll scroll) async {
    // Send as write with full data
    return write(scroll.key, scroll.data);
  }

  @override
  Future<NineResult<List<String>>> list(String prefix) async {
    try {
      final response = await _request(Request.list(_tag(), prefix));
      if (response.ok) {
        return Ok(response.paths ?? []);
      } else {
        return Err(_errorFromResponse(response));
      }
    } catch (e) {
      return Err(_errorFromException(e));
    }
  }

  @override
  NineResult<Stream<Scroll>> watch(String pattern) {
    if (_closed) return const Err(ClosedError());

    final tag = _tag();
    final controller = StreamController<Scroll>(
      onCancel: () {
        // Send unwatch request
        _watches.remove(tag);
        if (!_closed) {
          _request(Request.unwatch(tag)).ignore();
        }
      },
    );

    _watches[tag] = controller;

    // Send watch request asynchronously
    _request(Request.watch(tag, pattern)).then((response) {
      if (!response.ok) {
        controller.addError(_errorFromResponse(response));
        controller.close();
        _watches.remove(tag);
      }
      // If ok, server will push events with this tag
    }).catchError((e) {
      controller.addError(e);
      controller.close();
      _watches.remove(tag);
    });

    return Ok(controller.stream);
  }

  @override
  Future<NineResult<void>> close() async {
    if (_closed) return const Ok(null);
    _closed = true;

    // Cancel subscription
    await _subscription?.cancel();

    // Close connection
    await _connection.close();

    // Clean up
    _pending.clear();
    for (final controller in _watches.values) {
      await controller.close();
    }
    _watches.clear();

    return const Ok(null);
  }

  // ============================================================================
  // Error Conversion
  // ============================================================================

  NineError _errorFromResponse(Response response) {
    final code = response.code ?? 'internal';
    final msg = response.error ?? 'unknown error';

    return switch (code) {
      'not_found' => NotFoundError(msg),
      'invalid_path' => InvalidPathError(msg),
      'invalid_data' => InvalidDataError(msg),
      'permission' => PermissionError(msg),
      'closed' => const ClosedError(),
      'timeout' => const TimeoutError(),
      'connection' => ConnectionError(msg),
      'unavailable' => UnavailableError(msg),
      _ => InternalError(msg),
    };
  }

  NineError _errorFromException(Object e) {
    if (e is NineError) return e;
    if (e is SocketException) return ConnectionError(e.message);
    return InternalError(e.toString());
  }
}

/// AsyncNamespace - Async version of Namespace for network operations
///
/// Same five operations, but async.
/// Network is inherently async - pretending otherwise hides truth.
abstract interface class AsyncNamespace {
  Future<NineResult<Scroll?>> read(String path);
  Future<NineResult<Scroll>> write(String path, Map<String, dynamic> data);
  Future<NineResult<Scroll>> writeScroll(Scroll scroll);
  Future<NineResult<List<String>>> list(String prefix);
  NineResult<Stream<Scroll>> watch(String pattern); // Stream is already async
  Future<NineResult<void>> close();
}
