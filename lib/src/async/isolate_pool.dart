/// IsolatePool - CSP-style Parallel Execution for Heavy Operations
///
/// Dart's Isolates are true parallel threads with message passing (CSP).
/// This pool manages a set of worker isolates for CPU-intensive tasks:
/// - Encryption/decryption
/// - Hash computation
/// - JSON parsing of large payloads
///
/// ## Philosophy
///
/// "One Form, many instances" - the pool provides a single interface
/// to dispatch work, internally managing the complexity of isolate
/// lifecycle and message passing.
///
/// ## Dart Lesson: Isolate Communication
///
/// Isolates communicate via SendPort/ReceivePort (like Go channels).
/// Unlike threads, isolates share NO memory - all data is copied.
/// This eliminates data races but requires careful design.
///
/// ```dart
/// // Heavy work runs in parallel without blocking event loop
/// final result = await pool.compute(encryptData, plaintext);
/// ```
library;

import 'dart:async';
import 'dart:isolate';

/// Message sent to worker isolate
class _WorkRequest<T, R> {
  final int id;
  final R Function(T) work;
  final T data;
  final SendPort replyPort;

  _WorkRequest(this.id, this.work, this.data, this.replyPort);
}

/// Response from worker isolate
class _WorkResponse<T> {
  final int id;
  final T? result;
  final Object? error;

  _WorkResponse.success(this.id, this.result) : error = null;
  _WorkResponse.error(this.id, this.error) : result = null;
}

/// Worker isolate entry point
void _workerEntryPoint(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _WorkRequest) {
      try {
        final result = message.work(message.data);
        message.replyPort.send(_WorkResponse.success(message.id, result));
      } catch (e) {
        message.replyPort.send(_WorkResponse.error(message.id, e));
      }
    }
  });
}

/// IsolatePool - Manages a pool of worker isolates
///
/// ## Usage
///
/// ```dart
/// final pool = await IsolatePool.create(workers: 4);
///
/// // Heavy encryption in parallel
/// final encrypted = await pool.compute(
///   (data) => aesEncrypt(data),
///   plaintext,
/// );
///
/// // Clean up
/// await pool.close();
/// ```
class IsolatePool {
  final List<Isolate> _isolates = [];
  final List<SendPort> _ports = [];
  final Map<int, Completer<dynamic>> _pending = {};
  final ReceivePort _receivePort = ReceivePort();
  int _nextId = 0;
  int _nextWorker = 0;
  bool _closed = false;

  IsolatePool._();

  /// Create a pool with the specified number of workers
  ///
  /// Default is Platform.numberOfProcessors - 1, minimum 1.
  static Future<IsolatePool> create({int? workers}) async {
    final pool = IsolatePool._();
    final workerCount = workers ?? 2; // Conservative default

    // Listen for responses
    pool._receivePort.listen((message) {
      if (message is _WorkResponse) {
        final completer = pool._pending.remove(message.id);
        if (completer != null) {
          if (message.error != null) {
            completer.completeError(message.error!);
          } else {
            completer.complete(message.result);
          }
        }
      }
    });

    // Spawn workers
    for (var i = 0; i < workerCount; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _workerEntryPoint,
        receivePort.sendPort,
      );

      // Wait for worker to send its SendPort
      final workerPort = await receivePort.first as SendPort;
      pool._isolates.add(isolate);
      pool._ports.add(workerPort);
    }

    return pool;
  }

  /// Execute work in a worker isolate
  ///
  /// The function must be a top-level or static function
  /// (closures capture state that can't cross isolate boundaries).
  Future<R> compute<T, R>(R Function(T) work, T data) async {
    if (_closed) throw StateError('Pool is closed');

    final id = _nextId++;
    final completer = Completer<R>();
    _pending[id] = completer;

    // Round-robin worker selection
    final port = _ports[_nextWorker % _ports.length];
    _nextWorker++;

    port.send(_WorkRequest(id, work, data, _receivePort.sendPort));

    return completer.future;
  }

  /// Close the pool and kill all isolates
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    // Complete pending work with errors
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Pool closed'));
      }
    }
    _pending.clear();

    // Kill isolates
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.beforeNextEvent);
    }
    _isolates.clear();
    _ports.clear();
    _receivePort.close();
  }

  /// Number of workers in the pool
  int get workerCount => _ports.length;

  /// Number of pending tasks
  int get pendingCount => _pending.length;
}

/// Convenience function for one-off parallel computation
///
/// Creates a temporary isolate, runs the work, and cleans up.
/// Use IsolatePool for repeated operations.
///
/// ```dart
/// final hash = await computeAsync(
///   (data) => sha256.convert(data).toString(),
///   largeData,
/// );
/// ```
Future<R> computeAsync<T, R>(R Function(T) work, T data) async {
  return Isolate.run(() => work(data));
}
