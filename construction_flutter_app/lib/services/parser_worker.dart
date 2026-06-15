import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'pdf_ml_parser.dart';

/// Persistent background isolate that owns its own ONNX session (loaded once)
/// and runs the heavy part of PDF parsing — the 4x image decode, inference and
/// mask generation — off the UI thread. The lighter 2x layout analysis stays on
/// the main isolate, so this worker only needs the public [parseDecodedImage].
///
/// onnxruntime is FFI-based, so the native session works inside an isolate. If
/// anything here fails, callers fall back to main-thread parsing (see
/// PdfMlParser.parsePdf), so this can only speed things up — never break them.
class ParserWorker {
  ParserWorker._();
  static final ParserWorker instance = ParserWorker._();

  SendPort? _sendPort;
  Completer<void>? _ready;
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  Future<void> _ensureSpawned() {
    if (_sendPort != null) return Future.value();
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    () async {
      try {
        final model =
            (await rootBundle.load('assets/models/best.onnx')).buffer.asUint8List();
        final recv = ReceivePort();
        recv.listen((msg) {
          if (msg is SendPort) {
            _sendPort = msg;
            if (!ready.isCompleted) ready.complete();
          } else if (msg is Map && msg.containsKey('__id')) {
            final c = _pending.remove(msg['__id'] as int);
            if (c == null) return;
            if (msg.containsKey('__error')) {
              c.completeError(msg['__error'] as Object);
            } else {
              c.complete((msg['__result'] as Map).cast<String, dynamic>());
            }
          }
        });
        await Isolate.spawn(
          _entry,
          [recv.sendPort, TransferableTypedData.fromList([model])],
        );
      } catch (e) {
        if (!ready.isCompleted) ready.completeError(e);
        _ready = null;
      }
    }();
    return ready.future;
  }

  /// Runs [parseDecodedImage] in the worker. [rects] are the page-fraction
  /// region rects already computed on the main isolate (small 2x analysis).
  Future<Map<String, dynamic>> parse({
    required Uint8List bytes4x,
    required List<List<double>>? rects,
    required double mPerPoint,
    required double pageWidthPt,
    required String? pageText,
    required bool hasEmbeddedScale,
    double? userLongFt,
    double? userShortFt,
  }) async {
    await _ensureSpawned();
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _sendPort!.send({
      'id': id,
      'bytes4x': TransferableTypedData.fromList([bytes4x]),
      'rects': rects,
      'mPerPoint': mPerPoint,
      'pageWidthPt': pageWidthPt,
      'pageText': pageText,
      'hasEmbeddedScale': hasEmbeddedScale,
      'userLongFt': userLongFt,
      'userShortFt': userShortFt,
    });
    return completer.future;
  }

  // ── Isolate side ────────────────────────────────────────────────────────
  static void _entry(List<dynamic> args) async {
    final SendPort mainSend = args[0] as SendPort;
    final model = (args[1] as TransferableTypedData).materialize().asUint8List();

    OrtEnv.instance.init();
    PdfMlParser.session = OrtSession.fromBuffer(model, OrtSessionOptions());

    final port = ReceivePort();
    mainSend.send(port.sendPort);

    await for (final msg in port) {
      final m = msg as Map;
      final id = m['id'] as int;
      try {
        final bytes4x =
            (m['bytes4x'] as TransferableTypedData).materialize().asUint8List();
        final decoded = img.decodeImage(bytes4x);
        if (decoded == null) {
          mainSend.send({'__id': id, '__result': _failed});
          continue;
        }
        final rawRects = m['rects'] as List?;
        final rects = rawRects
            ?.map((r) => (r as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        final result = await PdfMlParser.parseDecodedImage(
          decoded,
          m['mPerPoint'] as double,
          m['pageWidthPt'] as double,
          pageText: m['pageText'] as String?,
          hasEmbeddedScale: m['hasEmbeddedScale'] as bool,
          userLongFt: m['userLongFt'] as double?,
          userShortFt: m['userShortFt'] as double?,
          regionRects: rects,
        );
        mainSend.send({'__id': id, '__result': result});
      } catch (e) {
        mainSend.send({'__id': id, '__error': e.toString()});
      }
    }
  }

  static const Map<String, dynamic> _failed = {
    'totalFloorArea': 0.0,
    'totalWallLength': 0.0,
    'floorCount': 1,
    'roomCounts': <String, int>{},
    'confidence': 0.1,
    'parserType': 'ml_pdf_failed',
  };
}
