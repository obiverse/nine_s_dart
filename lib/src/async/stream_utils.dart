/// Stream Utilities - Rx-style Reactive Patterns for 9S
///
/// Dart Streams are a first-class reactive primitive, combining
/// the ergonomics of RxJS with native async/await integration.
///
/// ## Key Patterns for 9S
///
/// 1. **Debounce**: Coalesce rapid writes (e.g., typing)
/// 2. **Throttle**: Rate-limit updates (e.g., sync events)
/// 3. **Batch**: Group changes into transactions
/// 4. **Distinct**: Skip duplicate values
/// 5. **Timeout**: Add deadlines to operations
///
/// ## Dart Lesson: StreamTransformer
///
/// StreamTransformers are the building blocks of stream pipelines.
/// They can filter, map, buffer, and transform events.
///
/// ```dart
/// final updates = store.watch('/doc/**')
///   .transform(debounce(Duration(milliseconds: 300)))
///   .transform(batch(Duration(seconds: 1)))
///   .listen(handleBatch);
/// ```
library;

import 'dart:async';

/// Debounce transformer - delays emission until no new events for duration
///
/// Useful for search-as-you-type, auto-save, etc.
///
/// ```dart
/// stream.transform(debounce(Duration(milliseconds: 300)))
/// ```
StreamTransformer<T, T> debounce<T>(Duration duration) {
  return _DebounceTransformer<T>(duration);
}

class _DebounceTransformer<T> implements StreamTransformer<T, T> {
  final Duration duration;

  _DebounceTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    final controller = StreamController<T>();
    Timer? timer;

    stream.listen(
      (data) {
        timer?.cancel();
        timer = Timer(duration, () => controller.add(data));
      },
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<T, T, RS, RT>(this);
}

/// Throttle transformer - emits at most once per duration
///
/// Useful for rate-limiting expensive operations.
///
/// ```dart
/// stream.transform(throttle(Duration(seconds: 1)))
/// ```
StreamTransformer<T, T> throttle<T>(Duration duration) {
  DateTime? lastEmit;

  return StreamTransformer<T, T>.fromHandlers(
    handleData: (data, sink) {
      final now = DateTime.now();
      if (lastEmit == null || now.difference(lastEmit!) >= duration) {
        lastEmit = now;
        sink.add(data);
      }
    },
  );
}

/// Batch transformer - groups events into lists over a duration
///
/// Useful for bulk operations, transaction batching.
///
/// ```dart
/// stream.transform(batch(Duration(seconds: 1)))
///   .listen((events) => processBatch(events));
/// ```
StreamTransformer<T, List<T>> batch<T>(Duration duration) {
  return _BatchTransformer<T>(duration);
}

class _BatchTransformer<T> implements StreamTransformer<T, List<T>> {
  final Duration duration;

  _BatchTransformer(this.duration);

  @override
  Stream<List<T>> bind(Stream<T> stream) {
    final controller = StreamController<List<T>>();
    List<T> buffer = [];
    Timer? timer;

    void flush() {
      if (buffer.isNotEmpty) {
        controller.add(List.unmodifiable(buffer));
        buffer = [];
      }
    }

    stream.listen(
      (data) {
        buffer.add(data);
        timer?.cancel();
        timer = Timer(duration, flush);
      },
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        flush();
        controller.close();
      },
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<T, List<T>, RS, RT>(this);
}

/// Distinct transformer - skips consecutive duplicate values
///
/// Uses equality check (can provide custom comparator).
///
/// ```dart
/// stream.transform(distinct((a, b) => a.id == b.id))
/// ```
StreamTransformer<T, T> distinct<T>([bool Function(T, T)? equals]) {
  T? previous;
  bool hasPrevious = false;

  return StreamTransformer<T, T>.fromHandlers(
    handleData: (data, sink) {
      final isDuplicate = hasPrevious &&
          (equals != null ? equals(previous as T, data) : previous == data);

      if (!isDuplicate) {
        hasPrevious = true;
        previous = data;
        sink.add(data);
      }
    },
  );
}

/// Sample transformer - emits the latest value at regular intervals
///
/// Useful for UI updates that shouldn't be too frequent.
///
/// ```dart
/// stream.transform(sample(Duration(milliseconds: 16)))  // ~60fps
/// ```
StreamTransformer<T, T> sample<T>(Duration interval) {
  return _SampleTransformer<T>(interval);
}

class _SampleTransformer<T> implements StreamTransformer<T, T> {
  final Duration interval;

  _SampleTransformer(this.interval);

  @override
  Stream<T> bind(Stream<T> stream) {
    final controller = StreamController<T>();
    T? latest;
    bool hasValue = false;
    Timer? timer;

    void emit() {
      if (hasValue) {
        controller.add(latest as T);
        hasValue = false;
      }
    }

    stream.listen(
      (data) {
        latest = data;
        hasValue = true;
        timer ??= Timer.periodic(interval, (_) => emit());
      },
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        emit();
        controller.close();
      },
    );

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<T, T, RS, RT>(this);
}

/// Buffer until transformer - buffers events until trigger emits
///
/// Useful for collecting changes until a save/commit trigger.
///
/// ```dart
/// final save = StreamController<void>();
/// stream.transform(bufferUntil(save.stream))
///   .listen((batch) => saveBatch(batch));
///
/// save.add(null);  // Triggers flush
/// ```
StreamTransformer<T, List<T>> bufferUntil<T>(Stream<void> trigger) {
  return _BufferUntilTransformer<T>(trigger);
}

class _BufferUntilTransformer<T> implements StreamTransformer<T, List<T>> {
  final Stream<void> trigger;

  _BufferUntilTransformer(this.trigger);

  @override
  Stream<List<T>> bind(Stream<T> stream) {
    final controller = StreamController<List<T>>();
    List<T> buffer = [];

    void flush() {
      if (buffer.isNotEmpty) {
        controller.add(List.unmodifiable(buffer));
        buffer = [];
      }
    }

    stream.listen(
      (data) => buffer.add(data),
      onError: controller.addError,
      onDone: () {
        flush();
        controller.close();
      },
    );

    trigger.listen((_) => flush());

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<T, List<T>, RS, RT>(this);
}

/// Merge multiple streams into one
///
/// ```dart
/// merge([stream1, stream2, stream3]).listen(handler);
/// ```
Stream<T> merge<T>(Iterable<Stream<T>> streams) {
  final controller = StreamController<T>();
  var active = streams.length;

  for (final stream in streams) {
    stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        active--;
        if (active == 0) controller.close();
      },
    );
  }

  return controller.stream;
}

/// Combine latest values from multiple streams
///
/// ```dart
/// combineLatest2(streamA, streamB, (a, b) => '$a:$b')
///   .listen(print);
/// ```
Stream<R> combineLatest2<A, B, R>(
  Stream<A> streamA,
  Stream<B> streamB,
  R Function(A, B) combiner,
) {
  final controller = StreamController<R>();
  A? latestA;
  B? latestB;
  bool hasA = false;
  bool hasB = false;

  void tryEmit() {
    if (hasA && hasB) {
      controller.add(combiner(latestA as A, latestB as B));
    }
  }

  streamA.listen(
    (a) {
      latestA = a;
      hasA = true;
      tryEmit();
    },
    onError: controller.addError,
  );

  streamB.listen(
    (b) {
      latestB = b;
      hasB = true;
      tryEmit();
    },
    onError: controller.addError,
  );

  return controller.stream;
}

/// Extension methods for fluent stream operations
extension StreamExtensions<T> on Stream<T> {
  /// Debounce this stream
  Stream<T> debounced(Duration duration) =>
      transform(debounce<T>(duration));

  /// Throttle this stream
  Stream<T> throttled(Duration duration) =>
      transform(throttle<T>(duration));

  /// Batch this stream
  Stream<List<T>> batched(Duration duration) =>
      transform(batch<T>(duration));

  /// Make this stream distinct
  Stream<T> distinctBy([bool Function(T, T)? equals]) =>
      transform(distinct<T>(equals));

  /// Sample this stream at intervals
  Stream<T> sampled(Duration interval) =>
      transform(sample<T>(interval));
}
