/// Protocol - The "How to Speak" of Networking
///
/// Defines message encoding/decoding for the wire.
/// The 9S wire protocol uses newline-delimited JSON.
///
/// ## The Wire Format (Section 6 of 9S Spec)
///
/// ```
/// Request:  {"tag": 1, "op": "read", "path": "/wallet/balance"}
/// Response: {"tag": 1, "ok": true, "scroll": {...}}
/// Event:    {"tag": 1, "event": true, "scroll": {...}}
/// ```
///
/// Tags enable multiplexing - multiple requests in flight on one connection.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../scroll/scroll.dart';

/// Operations in the 9S protocol
enum Op {
  read,
  write,
  list,
  watch,
  unwatch,
  close;

  String toJson() => name;

  static Op fromJson(String s) => Op.values.byName(s);
}

/// Request message
///
/// Sent from client to server.
class Request {
  /// Request tag for multiplexing
  final int tag;

  /// Operation to perform
  final Op op;

  /// Target path or pattern
  final String path;

  /// Data payload (for write)
  final Map<String, dynamic>? data;

  const Request({
    required this.tag,
    required this.op,
    required this.path,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'op': op.toJson(),
        'path': path,
        if (data != null) 'data': data,
      };

  factory Request.fromJson(Map<String, dynamic> json) => Request(
        tag: json['tag'] as int,
        op: Op.fromJson(json['op'] as String),
        path: json['path'] as String,
        data: json['data'] as Map<String, dynamic>?,
      );

  // Convenience constructors
  factory Request.read(int tag, String path) =>
      Request(tag: tag, op: Op.read, path: path);

  factory Request.write(int tag, String path, Map<String, dynamic> data) =>
      Request(tag: tag, op: Op.write, path: path, data: data);

  factory Request.list(int tag, String prefix) =>
      Request(tag: tag, op: Op.list, path: prefix);

  factory Request.watch(int tag, String pattern) =>
      Request(tag: tag, op: Op.watch, path: pattern);

  factory Request.unwatch(int tag) =>
      Request(tag: tag, op: Op.unwatch, path: '');

  factory Request.close(int tag) => Request(tag: tag, op: Op.close, path: '');
}

/// Response message
///
/// Sent from server to client.
class Response {
  /// Matches request tag
  final int tag;

  /// Success or failure
  final bool ok;

  /// Result scroll (for read/write)
  final Scroll? scroll;

  /// Result paths (for list)
  final List<String>? paths;

  /// Error message (if ok=false)
  final String? error;

  /// Error code (if ok=false)
  final String? code;

  /// True if this is a watch event (not a response)
  final bool event;

  const Response({
    required this.tag,
    required this.ok,
    this.scroll,
    this.paths,
    this.error,
    this.code,
    this.event = false,
  });

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'ok': ok,
        if (scroll != null) 'scroll': scroll!.toJson(),
        if (paths != null) 'paths': paths,
        if (error != null) 'error': error,
        if (code != null) 'code': code,
        if (event) 'event': true,
      };

  factory Response.fromJson(Map<String, dynamic> json) => Response(
        tag: json['tag'] as int,
        ok: json['ok'] as bool,
        scroll: json['scroll'] != null
            ? Scroll.fromJson(json['scroll'] as Map<String, dynamic>)
            : null,
        paths: (json['paths'] as List?)?.cast<String>(),
        error: json['error'] as String?,
        code: json['code'] as String?,
        event: json['event'] as bool? ?? false,
      );

  // Convenience constructors
  factory Response.ok(int tag, {Scroll? scroll, List<String>? paths}) =>
      Response(tag: tag, ok: true, scroll: scroll, paths: paths);

  factory Response.err(int tag, String error, [String? code]) =>
      Response(tag: tag, ok: false, error: error, code: code);

  factory Response.event(int tag, Scroll scroll) =>
      Response(tag: tag, ok: true, scroll: scroll, event: true);
}

/// Codec - Message encoding interface (JSON, MsgPack, etc.)
///
/// Encodes/decodes messages to/from bytes.
/// Separate from framing (how messages are delimited on the wire).
abstract interface class Codec {
  /// Encode a request to bytes (without framing)
  Uint8List encodeRequest(Request req);

  /// Encode a response to bytes (without framing)
  Uint8List encodeResponse(Response res);

  /// Decode bytes to a request (without framing)
  Request decodeRequest(Uint8List bytes);

  /// Decode bytes to a response (without framing)
  Response decodeResponse(Uint8List bytes);
}

/// Framer - Message framing interface (newline, length-prefix, etc.)
///
/// Frames/unframes messages for the wire.
/// Separate from encoding (how messages are serialized).
abstract interface class Framer {
  /// Add framing to encoded message
  Uint8List frame(Uint8List encoded);

  /// Split a buffer into complete framed messages
  /// Returns (messages, remaining) where remaining is incomplete data.
  (List<Uint8List>, Uint8List) splitMessages(Uint8List buffer);

  /// StreamTransformer that frames byte chunks into complete messages
  StreamTransformer<Uint8List, Uint8List> messageFramer();
}

/// Protocol - Combined Codec + Framer for convenience
///
/// The full wire protocol combines encoding with framing.
/// Use this interface when you want the complete package.
abstract interface class Protocol implements Codec {
  /// The framer used by this protocol
  Framer get framer;
}

/// NewlineFramer - Frames messages with newline delimiter
///
/// Each message is delimited by a newline character.
/// Simple, debuggable, universally supported.
class NewlineFramer implements Framer {
  const NewlineFramer();

  static const _newline = 0x0A; // '\n'

  @override
  Uint8List frame(Uint8List encoded) {
    final framed = Uint8List(encoded.length + 1);
    framed.setAll(0, encoded);
    framed[encoded.length] = _newline;
    return framed;
  }

  @override
  (List<Uint8List>, Uint8List) splitMessages(Uint8List buffer) {
    final messages = <Uint8List>[];
    var start = 0;

    for (var i = 0; i < buffer.length; i++) {
      if (buffer[i] == _newline) {
        messages.add(Uint8List.sublistView(buffer, start, i));
        start = i + 1;
      }
    }

    final remaining = start < buffer.length
        ? Uint8List.sublistView(buffer, start)
        : Uint8List(0);

    return (messages, remaining);
  }

  @override
  StreamTransformer<Uint8List, Uint8List> messageFramer() {
    return _MessageFramerTransformer(this);
  }
}

/// JsonCodec - Encodes messages as JSON
///
/// Pure encoding without framing.
class JsonCodec implements Codec {
  const JsonCodec();

  static const _encoder = Utf8Encoder();
  static const _decoder = Utf8Decoder();

  @override
  Uint8List encodeRequest(Request req) {
    final json = jsonEncode(req.toJson());
    return Uint8List.fromList(_encoder.convert(json));
  }

  @override
  Uint8List encodeResponse(Response res) {
    final json = jsonEncode(res.toJson());
    return Uint8List.fromList(_encoder.convert(json));
  }

  @override
  Request decodeRequest(Uint8List bytes) {
    final json = _decoder.convert(bytes);
    final map = jsonDecode(json) as Map<String, dynamic>;
    return Request.fromJson(map);
  }

  @override
  Response decodeResponse(Uint8List bytes) {
    final json = _decoder.convert(bytes);
    final map = jsonDecode(json) as Map<String, dynamic>;
    return Response.fromJson(map);
  }
}

/// JSON-newline protocol (default)
///
/// Each message is a JSON object followed by newline.
/// Combines JsonCodec with NewlineFramer.
class JsonLineProtocol implements Protocol {
  const JsonLineProtocol();

  static const _codec = JsonCodec();
  static const _framer = NewlineFramer();

  @override
  Framer get framer => _framer;

  @override
  Uint8List encodeRequest(Request req) => _codec.encodeRequest(req);

  @override
  Uint8List encodeResponse(Response res) => _codec.encodeResponse(res);

  @override
  Request decodeRequest(Uint8List bytes) => _codec.decodeRequest(bytes);

  @override
  Response decodeResponse(Uint8List bytes) => _codec.decodeResponse(bytes);

  /// Split a buffer into complete messages (legacy static method)
  ///
  /// Returns (messages, remaining) where remaining is incomplete data.
  static (List<Uint8List>, Uint8List) splitMessages(Uint8List buffer) {
    return _framer.splitMessages(buffer);
  }

  /// StreamTransformer that frames byte chunks into complete messages (legacy)
  ///
  /// Accumulates incoming bytes and emits complete newline-delimited messages.
  /// Usage:
  /// ```dart
  /// connection.incoming
  ///   .transform(JsonLineProtocol.messageFramer())
  ///   .listen((message) => print(utf8.decode(message)));
  /// ```
  static StreamTransformer<Uint8List, Uint8List> messageFramer() {
    return _framer.messageFramer();
  }
}

/// StreamTransformer implementation for message framing
///
/// Dart Lesson: StreamTransformer provides a clean way to process streams.
/// The bind() method wraps the source stream and returns a new stream.
class _MessageFramerTransformer
    implements StreamTransformer<Uint8List, Uint8List> {
  final Framer _framer;

  _MessageFramerTransformer(this._framer);

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) {
    return Stream.eventTransformed(
      stream,
      (sink) => _MessageFramerSink(sink, _framer),
    );
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<Uint8List, Uint8List, RS, RT>(this);
}

/// EventSink that accumulates bytes and emits complete messages
class _MessageFramerSink implements EventSink<Uint8List> {
  final EventSink<Uint8List> _output;
  final Framer _framer;
  Uint8List _buffer = Uint8List(0);

  _MessageFramerSink(this._output, this._framer);

  @override
  void add(Uint8List data) {
    // Append to buffer
    if (_buffer.isEmpty) {
      _buffer = data;
    } else {
      final newBuffer = Uint8List(_buffer.length + data.length);
      newBuffer.setAll(0, _buffer);
      newBuffer.setAll(_buffer.length, data);
      _buffer = newBuffer;
    }

    // Split into messages using the framer
    final (messages, remaining) = _framer.splitMessages(_buffer);
    _buffer = remaining;

    // Emit complete messages
    for (final msg in messages) {
      _output.add(msg);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _output.addError(error, stackTrace);
  }

  @override
  void close() {
    // If there's remaining data, it's an incomplete message - discard or error
    // For robustness, we just close without error
    _output.close();
  }
}
