import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/foundation.dart';
import 'parser_worker.dart';

class PdfMlParser {
  static OrtSession? _session;
  static set session(OrtSession? val) => _session = val;
  static const int _inputSize = 512;
  static const List<String> _classNames = [
    'wall', 'room', 'door', 'window',
    'bathroom', 'kitchen', 'bedroom', 'livingroom'
  ];
  static const Set<String> _roomClasses = {
    'room', 'bathroom', 'kitchen', 'bedroom', 'livingroom'
  };
  // Gross footprint -> built-up efficiency for single-region residential plans.
  // Matches the DXF parser convention (cad_parser.py residential = 0.82).
  static const double _residentialEfficiency = 0.82;

  // Lazy load ONNX session
  static Future<OrtSession> _getSession() async {
    if (_session != null) return _session!;
    
    debugPrint('[PDF_ML] Loading ONNX model from assets...');
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    
    final modelBytes = await rootBundle.load(
        'assets/models/best.onnx');
    final bytes = modelBytes.buffer.asUint8List();
    
    _session = OrtSession.fromBuffer(bytes, sessionOptions);
    debugPrint('[PDF_ML] ONNX model loaded successfully');
    return _session!;
  }

  // Detect the drawing scale ratio (the NN in 1:NN) from embedded PDF text.
  // The previous version took the FIRST `1:NN` token, which on multi-detail
  // sheets is often a small detail scale (e.g. "1/2") that gets rejected,
  // silently falling back to the 1:75 default. Instead, prefer a ratio that
  // directly follows the word "SCALE", otherwise take the most common valid
  // standalone ratio on the page. Returns null when no scale is embedded.
  static int? _detectEmbeddedScaleRatio(String text) {
    final adj = <int, int>{};
    final scaleRe = RegExp(r'SCALE\s*:?\s*1[:/](\d+)', caseSensitive: false);
    for (final m in scaleRe.allMatches(text)) {
      final r = int.tryParse(m.group(1) ?? '');
      if (r != null && r >= 20 && r <= 500) adj[r] = (adj[r] ?? 0) + 1;
    }
    if (adj.isNotEmpty) return _mostCommon(adj);

    final allRe = RegExp(r'(?<![\d.])1[:/](\d+)');
    final counts = <int, int>{};
    for (final m in allRe.allMatches(text)) {
      final r = int.tryParse(m.group(1) ?? '');
      if (r != null && r >= 20 && r <= 500) counts[r] = (counts[r] ?? 0) + 1;
    }
    if (counts.isNotEmpty) return _mostCommon(counts);
    return null;
  }

  static int _mostCommon(Map<int, int> freq) {
    int best = freq.keys.first;
    int bestCount = -1;
    freq.forEach((k, v) {
      if (v > bestCount) {
        bestCount = v;
        best = k;
      }
    });
    return best;
  }

  // All feet-dimension tokens (e.g. "30'") on the plan, used both to find the
  // overall building dimensions and to sanity-check them against room sizes.
  static List<int> _feetTokens(String text) {
    final re = RegExp(r"(\d{1,3})'");
    final vals = <int>[];
    for (final m in re.allMatches(text)) {
      final v = int.tryParse(m.group(1) ?? '');
      if (v != null && v >= 3 && v <= 200) vals.add(v);
    }
    return vals;
  }

  // Derive metres-per-point by mapping the building's pixel footprint to its
  // overall dimensions. Returns null when the dimensions can't be trusted, so
  // the caller can fall back to asking the user. Guards:
  //  - need at least two distinct dimensions and a positive footprint;
  //  - the largest printed length must clearly stand out from the median
  //    (otherwise only room sizes are printed, not the overall extent — e.g.
  //    1BHK 24x22, whose drawing prints 12'/11' rooms but no 24'/22' overall);
  //  - the footprint aspect ratio must roughly match the dimensions' ratio;
  //  - the resulting 1:NN must be physically plausible.
  static double? _scaleFromDims(
      String text, double bboxLongPt, double bboxShortPt) {
    final feet = _feetTokens(text);
    if (feet.length < 2 || bboxShortPt <= 0) return null;
    final distinct = feet.toSet().toList()..sort((a, b) => b.compareTo(a));
    if (distinct.length < 2) return null;
    final double longFt = distinct[0].toDouble();
    final double shortFt = distinct[1].toDouble();

    final sorted = List<int>.from(feet)..sort();
    final double median = sorted[sorted.length ~/ 2].toDouble();
    if (longFt < 2.0 * median) return null; // overall extent not printed

    final double aspectRatio =
        (bboxLongPt / bboxShortPt) / (longFt / shortFt);
    if (aspectRatio < 0.55 || aspectRatio > 1.8) return null;

    return _mppFromDims(longFt, shortFt, bboxLongPt, bboxShortPt);
  }

  // Metres-per-point from a known building footprint (in feet) and its pixel
  // span (in points). Shared by auto dimension detection and user-entered
  // dimensions. Returns null if the implied 1:NN is implausible.
  static double? _mppFromDims(
      double longFt, double shortFt, double bboxLongPt, double bboxShortPt) {
    if (bboxLongPt <= 0 || bboxShortPt <= 0) return null;
    final double mpp = ((longFt * 0.3048 / bboxLongPt) +
            (shortFt * 0.3048 / bboxShortPt)) /
        2;
    final double ratio = mpp * 1000 / 0.3528;
    if (ratio < 20 || ratio > 300) return null;
    return mpp;
  }

  // Preprocess image for ONNX (letterbox resize to 512x512)
  static Float32List _preprocessImage(img.Image image) {
    final int origW = image.width;
    final int origH = image.height;
    final double scale = _inputSize / math.max(origW, origH);
    final int newW = (origW * scale).round();
    final int newH = (origH * scale).round();

    // Resize
    final resized = img.copyResize(
        image, width: newW, height: newH);
    
    // Create padded 512x512 black image
    final padded = img.Image(
        width: _inputSize, height: _inputSize);
    img.fill(padded, color: img.ColorRgb8(0, 0, 0));
    img.compositeImage(padded, resized, dstX: 0, dstY: 0);

    // Normalize to Float32 [0,1] in NCHW format
    final tensor = Float32List(
        1 * 3 * _inputSize * _inputSize);
    int idx = 0;
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final pixel = padded.getPixel(x, y);
          double val;
          if (c == 0) val = pixel.r / 255.0;
          else if (c == 1) val = pixel.g / 255.0;
          else val = pixel.b / 255.0;
          tensor[idx++] = val;
        }
      }
    }
    return tensor;
  }

  // Run ONNX inference and return detections
  static Future<List<Map<String, dynamic>>> _runInference(
      img.Image image) async {
    debugPrint('[PDF_ML] Running inference on ${image.width}x${image.height} image');
    final session = await _getSession();
    final inputTensor = _preprocessImage(image);
    
    final shape = [1, 3, _inputSize, _inputSize];
    final inputOrt = OrtValueTensor.createTensorWithDataList(
        inputTensor, shape);
    
    final inputs = {'images': inputOrt};
    final outputs = await session.runAsync(
        OrtRunOptions(), inputs);
    
    // Log exact shapes
    if (outputs != null) {
      for (int i = 0; i < outputs.length; i++) {
        debugPrint('[PDF_ML_TENSOR] output[$i] '
            'type=${outputs[i]?.value.runtimeType}');
        if (outputs[i]?.value is List) {
          final val = outputs[i]!.value as List;
          debugPrint('[PDF_ML_TENSOR] output[$i] '
              'length=${val.length}');
          if (val.isNotEmpty && val[0] is List) {
            final inner = val[0] as List;
            debugPrint('[PDF_ML_TENSOR] output[$i][0] '
                'length=${inner.length}');
            if (inner.isNotEmpty && inner[0] is List) {
              final inner2 = inner[0] as List;
              debugPrint('[PDF_ML_TENSOR] output[$i][0][0] '
                  'length=${inner2.length}');
            }
          }
        }
      }
      
      final protos1 = outputs[1]!.value as List;
      final batch1 = protos1[0] as List;
      final mask0 = batch1[0] as List;
      final row0 = mask0[0] as List;
      debugPrint('[PDF_ML_PROTO] '
          'batch=${protos1.length} '
          'masks=${batch1.length} '
          'rows=${mask0.length} '
          'cols=${row0.length}');
    }
    
    inputOrt.release();
    
    if (outputs == null || outputs.isEmpty || outputs[0] == null) {
      return <Map<String, dynamic>>[];
    }
    
    // outputs[0]: boxes [1, 116, 8400]
    final boxesData = outputs[0]!.value as List;
    
    // Parse detections with NMS
    final detections = <Map<String, dynamic>>[];
    const double confThresh = 0.25;
    const int numClasses = 8;
    
    // boxesData is [1][116][8400] — flatten to [116][8400]
    final boxes = boxesData[0] as List;
    final numAnchors = (boxes[0] as List).length;
    
    final List<List<double>> candidates = [];
    final List<int> classIds = [];
    final List<double> scores = [];
    
    for (int i = 0; i < numAnchors; i++) {
      double maxScore = 0;
      int bestClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = (boxes[4 + c] as List)[i] as double;
        if (score > maxScore) {
          maxScore = score;
          bestClass = c;
        }
      }
      if (maxScore >= confThresh) {
        final cx = (boxes[0] as List)[i] as double;
        final cy = (boxes[1] as List)[i] as double;
        final bw = (boxes[2] as List)[i] as double;
        final bh = (boxes[3] as List)[i] as double;
        candidates.add([cx, cy, bw, bh]);
        classIds.add(bestClass);
        scores.add(maxScore);
      }
    }
    
    // Simple NMS by area overlap
    final kept = _nms(candidates, scores, 0.45);
    
    final double origW = image.width.toDouble();
    final double origH = image.height.toDouble();
    final double scale = math.max(origW, origH) / _inputSize;
    final double scaleX = scale;
    final double scaleY = scale;
    
    // Read the 32 prototype masks straight from the ONNX output (shape
    // [1,32,P,P]) instead of copying them into a fresh nested list — saves a
    // ~0.5M-double allocation per region.
    final masks32 = (outputs[1]!.value as List)[0] as List;

    final maskStart = DateTime.now();
    
    for (final idx in kept) {
      final cx = candidates[idx][0];
      final cy = candidates[idx][1];
      final bw = candidates[idx][2];
      final bh = candidates[idx][3];
      
      final x1 = ((cx - bw/2) * scaleX).clamp(0.0, origW);
      final y1 = ((cy - bh/2) * scaleY).clamp(0.0, origH);
      final x2 = ((cx + bw/2) * scaleX).clamp(0.0, origW);
      final y2 = ((cy + bh/2) * scaleY).clamp(0.0, origH);
      
      // Filter oversized detections (void filter)
      final bboxW = x2 - x1;
      final bboxH = y2 - y1;
      if (bboxW > 0.8 * origW || bboxH > 0.8 * origH) {
        continue;
      }
      
      final className = _classNames[classIds[idx]];
      
      // Extract 32 mask coefficients
      final boxes = boxesData[0] as List;
      final maskCoeffs = <double>[];
      for (int m = 12; m < 44; m++) {
        final row = boxes[m] as List;
        maskCoeffs.add((row[idx] as num).toDouble());
      }
      
      // Generate mask
      final mask = _generateMask(maskCoeffs, masks32);
      
      debugPrint('[PDF_ML_BBOX_CHECK] '
          'passing x1=$x1 y1=$y1 x2=$x2 y2=$y2 '
          'origW=$origW origH=$origH');

      // Count actual mask pixels
      final areaPx = _countMaskPixels(
          mask, x1, y1, x2, y2, origW, origH);
      
      if (_roomClasses.contains(className)) {
        debugPrint('[PDF_ML_DET] $className '
            'areaPx=${areaPx.toStringAsFixed(0)} '
            'bbox=${x1.toStringAsFixed(0)},${y1.toStringAsFixed(0)}'
            '-${x2.toStringAsFixed(0)},${y2.toStringAsFixed(0)} '
            'conf=${scores[idx].toStringAsFixed(2)}');
      }
      
      detections.add({
        'className': className,
        'conf': scores[idx],
        'areaPx': areaPx,
        'bbox': [x1, y1, x2, y2],
      });
    }
    
    final maskMs = DateTime.now()
        .difference(maskStart).inMilliseconds;
    debugPrint('[PDF_ML] Mask generation: ${maskMs}ms '
        'for ${kept.length} detections');
    
    for (final o in outputs) { o?.release(); }
    return detections;
  }

  // Simple NMS implementation
  static List<int> _nms(
      List<List<double>> boxes,
      List<double> scores,
      double iouThresh) {
    final indices = List.generate(scores.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    
    final kept = <int>[];
    final suppressed = List<bool>.filled(scores.length, false);
    
    for (final i in indices) {
      if (suppressed[i]) continue;
      kept.add(i);
      for (final j in indices) {
        if (i == j || suppressed[j]) continue;
        if (_iou(boxes[i], boxes[j]) > iouThresh) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  static double _iou(List<double> a, List<double> b) {
    final ax1 = a[0] - a[2]/2;
    final ay1 = a[1] - a[3]/2;
    final ax2 = a[0] + a[2]/2;
    final ay2 = a[1] + a[3]/2;
    final bx1 = b[0] - b[2]/2;
    final by1 = b[1] - b[3]/2;
    final bx2 = b[0] + b[2]/2;
    final by2 = b[1] + b[3]/2;
    
    final ix1 = math.max(ax1, bx1);
    final iy1 = math.max(ay1, by1);
    final ix2 = math.min(ax2, bx2);
    final iy2 = math.min(ay2, by2);
    
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    final aArea = (ax2-ax1) * (ay2-ay1);
    final bArea = (bx2-bx1) * (by2-by1);
    return inter / (aArea + bArea - inter);
  }

  static Future<int> _selectBestPage(
      sf.PdfDocument doc, String pdfPath) async {
    
    if (doc.pages.count == 1) return 0;
    
    int bestPage = 0;
    int bestScore = -9999;
    
    final extractor = sf.PdfTextExtractor(doc);
    
    for (int i = 0; i < doc.pages.count; i++) {
      try {
        final text = extractor.extractText(
            startPageIndex: i, endPageIndex: i)
            .toUpperCase();
        
        int score = 0;
        
        // Strong positive signals - this is a floor plan page
        if (text.contains('FLOOR PLAN')) score += 150;
        if (text.contains('FLOOR PLAN:')) score += 150;
        if (text.contains('MEMBER RESTROOM')) score += 120;
        if (text.contains('RESTROOM PLAN')) score += 120;
        if (text.contains('SCALE: 1:')) score += 100;
        if (text.contains('SCALE:1:')) score += 100;
        if (text.contains('PLAN\n')) score += 80;
        if (text.contains('\nPLAN')) score += 80;
        
        // Room labels indicate floor plan content
        if (text.contains('BED ROOM')) score += 60;
        if (text.contains('BEDROOM')) score += 60;
        if (text.contains('KITCHEN')) score += 50;
        if (text.contains('BATHROOM')) score += 50;
        if (text.contains('LIVING ROOM')) score += 50;
        if (text.contains('WOMEN')) score += 40;
        if (text.contains('MEN\'S')) score += 40;
        if (text.contains('RESTROOM')) score += 40;
        if (text.contains('PARKING')) score += 30;
        
        // Dimension annotations indicate drawing content
        final dimMatches = RegExp(r"\d+'\s*[Xx]\s*\d+'")
            .allMatches(text).length;
        score += dimMatches * 20;
        
        // Negative signals - skip these pages
        if (text.contains('TITLE SHEET')) score -= 200;
        if (text.contains('DRAWING INDEX')) score -= 150;
        if (text.contains('ABBREVIATIONS')) score -= 100;
        if (text.contains('ELEVATION')) score -= 60;
        if (text.contains('SECTION')) score -= 60;
        if (text.contains('DETAIL')) score -= 80;
        if (text.contains('SCHEDULE')) score -= 40;
        if (text.contains('SITE PLAN')) score -= 40;
        if (text.contains('VICINITY MAP')) score -= 80;
        
        debugPrint('[PDF_PAGE] Page ${i+1} score=$score');
        
        if (score > bestScore) {
          bestScore = score;
          bestPage = i;
        }
      } catch (_) {}
    }
    
    debugPrint('[PDF_PAGE] Selected page ${bestPage+1} '
        'with score=$bestScore');
    return bestPage;
  }

  // Drops columns that are clearly not floor plans (demolition / reflected
  // ceiling / notes / schedules), matching the backend region filter. Text
  // lines are matched to a column by their x-centre, so this is robust to the
  // PDF text origin convention. Never returns an empty list.
  static List<List<double>> _filterRegionsByText(List<List<double>> rects,
      List<sf.TextLine> lines, double pageW, double pageH) {
    const roomWords = [
      'WOMEN', 'MEN', 'RESTROOM', 'WASHROOM', 'TOILET', 'ROOM', 'OFFICE', 'PLAN'
    ];
    final kept = <List<double>>[];
    for (final r in rects) {
      // Shrink 20pt on each horizontal side so a divider's text isn't shared.
      final double rx0 = r[0] * pageW + 20, rx1 = r[2] * pageW - 20;
      final sb = StringBuffer();
      for (final ln in lines) {
        final double cx = ln.bounds.left + ln.bounds.width / 2;
        if (cx >= rx0 && cx <= rx1) {
          sb.write(ln.text.toUpperCase());
          sb.write(' ');
        }
      }
      final t = sb.toString();
      bool exclude = t.contains('DEMO') ||
          t.contains('CEILING') ||
          t.contains('REFLECTED');
      if (!exclude &&
          (t.contains('NOTE') ||
              t.contains('SCHEDULE') ||
              t.contains('SPECIFICATION') ||
              t.contains('LEGEND'))) {
        exclude = !roomWords.any(t.contains);
      }
      if (!exclude) kept.add(r);
      if (exclude) debugPrint('[PDF_SEG] Excluded non-plan column x=$rx0-$rx1');
    }
    return kept.isEmpty ? rects : kept;
  }

  // Renders a small native 2x layout-analysis image and returns the floor-plan
  // region rects. Falls back to a single full-page region on any failure.
  static Future<List<List<double>>> _detectRegionsFromPage(
      px.PdfPage page) async {
    const fullPage = <List<double>>[
      [0.0, 0.0, 1.0, 1.0]
    ];
    try {
      // Low-res analysis render is enough for region detection (relative
      // coords). Cap the longest side to ~3000px so huge sheets don't OOM here.
      double s = 2.0;
      final double longest = math.max(page.width, page.height);
      if (longest * s > 3000) s = 3000 / longest;
      s = s.clamp(0.5, 2.0);
      final analysis = await page.render(
        width: page.width * s,
        height: page.height * s,
        format: px.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 80,
      );
      if (analysis == null) return fullPage;
      final decoded = img.decodeImage(analysis.bytes);
      if (decoded == null) return fullPage;
      return _detectRegionRects(decoded);
    } catch (e) {
      debugPrint('[PDF_ML] Region detection failed: $e');
      return fullPage;
    }
  }

  // Content-based sheet segmentation (port of the backend sheet_segmenter).
  // Operates on a small, natively-rendered analysis image (crisp vector lines)
  // to find the floor-plan band and any side-by-side columns. Returns regions
  // as page-fraction rects [x0,y0,x1,y1]; [[0,0,1,1]] means a single full page.
  // 4x renders pack in too much detail and wash out the band, so analysis must
  // run on a ~2x native render — never on the high-res inference image.
  static List<List<double>> _detectRegionRects(img.Image a) {
    final int h = a.height, w = a.width;
    final bytes = a.getBytes(order: img.ChannelOrder.rgb);

    // Horizontal projection: dark-pixel count per row.
    final rowInk = List<double>.filled(h, 0);
    for (int y = 0; y < h; y++) {
      final int base = y * w * 3;
      int cnt = 0;
      for (int x = 0; x < w; x++) {
        final int i = base + x * 3;
        if (bytes[i] + bytes[i + 1] + bytes[i + 2] < 600) cnt++;
      }
      rowInk[y] = cnt.toDouble();
    }
    final band = _detectRowBand(rowInk, h);
    final double y0f = band[0], y1f = band[1];

    // A tall band means the plan fills the page: treat as a single region.
    if (y1f - y0f > 0.55) {
      return [
        [0.0, 0.0, 1.0, 1.0]
      ];
    }

    // Vertical projection within the band → column dividers (ink valleys).
    final int yb0 = (y0f * h).floor().clamp(0, h - 1);
    final int yb1 = (y1f * h).ceil().clamp(1, h);
    final colInk = List<double>.filled(w, 0);
    for (int y = yb0; y < yb1; y++) {
      final int base = y * w * 3;
      for (int x = 0; x < w; x++) {
        final int i = base + x * 3;
        if (bytes[i] + bytes[i + 1] + bytes[i + 2] < 600) colInk[x] += 1;
      }
    }
    final dividers = _detectColumnDividers(colInk, w);

    final xs = <double>[0.0, ...dividers, 1.0];
    final rects = <List<double>>[];
    for (int i = 0; i < xs.length - 1; i++) {
      double x0 = xs[i], x1 = xs[i + 1];
      // Small safety overlap so walls on a divider aren't cut off.
      if (i > 0) x0 = math.max(0.0, x0 - 0.005);
      if (i < xs.length - 2) x1 = math.min(1.0, x1 + 0.005);
      rects.add([x0, y0f, x1, y1f]);
    }
    return rects;
  }

  // Densest horizontal band of drawing ink, as [y0,y1] page fractions.
  static List<double> _detectRowBand(List<double> rowInk, int h) {
    final int win = math.max(1, (h * 0.05).round());
    final sm = _boxAverage(rowInk, win);
    final double mean = sm.reduce((a, b) => a + b) / sm.length;
    final double thr = mean * 0.6;

    double bestTotal = -1;
    int bestS = 0, bestE = 0;
    bool inBand = false;
    int s = 0;
    void closeBand(int end) {
      if (end - s > h * 0.15) {
        double tot = 0;
        for (int k = s; k < end; k++) {
          tot += rowInk[k];
        }
        if (tot > bestTotal) {
          bestTotal = tot;
          bestS = s;
          bestE = end;
        }
      }
    }

    for (int y = 0; y < h; y++) {
      final bool active = sm[y] > thr;
      if (active && !inBand) {
        inBand = true;
        s = y;
      } else if (!active && inBand) {
        inBand = false;
        closeBand(y);
      }
    }
    if (inBand) closeBand(h);

    if (bestTotal < 0) return [0.58, 0.90];
    final double pad = h * 0.02;
    return [
      math.max(0, bestS - pad) / h,
      math.min(h.toDouble(), bestE + pad) / h,
    ];
  }

  // Centre fractions of ink valleys between side-by-side floor plans.
  static List<double> _detectColumnDividers(List<double> colInk, int w) {
    final int win = math.max(1, (w * 0.02).round());
    final sm = _boxAverage(colInk, win);
    final double mean = sm.reduce((a, b) => a + b) / sm.length;
    final double thr = mean * 0.35;

    final dividers = <double>[];
    bool inValley = false;
    int vs = 0;
    for (int x = 0; x < w; x++) {
      final bool valley = sm[x] < thr;
      if (valley && !inValley) {
        inValley = true;
        vs = x;
      } else if (!valley && inValley) {
        inValley = false;
        if (w * 0.02 < vs && vs < w * 0.98 && (x - vs) > w * 0.01) {
          dividers.add((vs + x) / 2 / w);
        }
      }
    }
    return dividers;
  }

  // Centered moving average (zero-padded, divided by the window). Matches
  // numpy convolve(x, ones(win)/win, mode='same') closely enough for the
  // threshold-based band/valley detection above.
  static List<double> _boxAverage(List<double> x, int win) {
    final int n = x.length;
    final prefix = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }
    final out = List<double>.filled(n, 0);
    final int half = (win - 1) ~/ 2;
    for (int i = 0; i < n; i++) {
      final int a = math.max(0, i - half);
      final int b = math.min(n, i - half + win);
      out[i] = (prefix[b] - prefix[a]) / win;
    }
    return out;
  }

  // Main entry point. [userLongFt]/[userShortFt] let the caller supply the
  // building's overall dimensions (in feet) when the drawing carries neither an
  // embedded 1:NN scale nor readable overall dimensions (see 'ml_pdf_needs_scale').
  static Future<Map<String, dynamic>> parsePdf(
      String pdfPath, {double? userLongFt, double? userShortFt}) async {
    try {
      debugPrint('[PDF_ML] Starting parsePdf: $pdfPath');
      
      final bytes = await File(pdfPath).readAsBytes();
      final sfDoc = sf.PdfDocument(inputBytes: bytes);
      final bestPageIndex = await _selectBestPage(sfDoc, pdfPath);
      final extractor = sf.PdfTextExtractor(sfDoc);
      final pageText = extractor.extractText(
          startPageIndex: bestPageIndex, endPageIndex: bestPageIndex);
      // Text lines with bounds, used to exclude non-plan columns (demolition /
      // notes / schedules) from multi-view sheets — see _filterRegionsByText.
      final textLines = extractor.extractTextLines(
          startPageIndex: bestPageIndex, endPageIndex: bestPageIndex);
      final sfPageSize = sfDoc.pages[bestPageIndex].size;
      sfDoc.dispose();

      final embeddedRatio = _detectEmbeddedScaleRatio(pageText);
      final mPerPoint = embeddedRatio != null
          ? (0.3528 * embeddedRatio) / 1000.0
          : (0.3528 * 75) / 1000.0;
      debugPrint('[PDF_ML] Scale: '
          '${embeddedRatio != null ? "1:$embeddedRatio (embedded)" : "none (dims/default)"}');
      
      final document = await px.PdfDocument.openFile(pdfPath);
      debugPrint('[PDF_ML] Document opened, pages: ${document.pagesCount}');
      
      final page = await document.getPage(bestPageIndex + 1);
      final double pageWidthPt = page.width;
      debugPrint('[PDF_ML] Page opened: ${page.width}x${page.height}');

      // Content-based segmentation only makes sense for large multi-view
      // architectural sheets (e.g. ARCH-D). Normal residential pages (A4-ish)
      // are a single plan — splitting them on internal gaps would wrongly cut
      // one building into pieces and bypass the footprint model, so treat them
      // as a single region (also skips the extra analysis render).
      final bool largeSheet = math.max(page.width, page.height) > 1600;
      var regionRects = largeSheet
          ? await _detectRegionsFromPage(page)
          : const [
              [0.0, 0.0, 1.0, 1.0]
            ];
      if (regionRects.length > 1) {
        regionRects = _filterRegionsByText(
            regionRects, textLines, sfPageSize.width, sfPageSize.height);
      }
      debugPrint('[PDF_ML] Layout: ${regionRects.length} region(s) '
          '(largeSheet=$largeSheet)');

      // Adaptive render scale. A fixed 4x OOM-crashes on large multi-view IFT
      // sheets (e.g. a 36"×24" ARCH-D page ≈ 2592pt → 4x ≈ 70MP ≈ a 280MB
      // bitmap). Cap the longest rendered side to ~6000px. The geometry math
      // self-calibrates to the actual image width (ptPerPx = pageWidthPt /
      // decoded.width) and ML inference uses relative coords, so a lower scale
      // only saves memory — it changes neither the scale result nor inference.
      // Small residential pages stay at 4x (no regression).
      double renderScale = 4.0;
      final double longestPt = math.max(page.width, page.height);
      if (longestPt * renderScale > 6000) {
        renderScale = 6000 / longestPt;
      }
      renderScale = renderScale.clamp(1.0, 4.0);
      debugPrint('[PDF_ML] Render scale: ${renderScale.toStringAsFixed(2)}x '
          '(page ${page.width.toStringAsFixed(0)}x${page.height.toStringAsFixed(0)}pt)');

      final pageImage = await page.render(
        width: page.width * renderScale,
        height: page.height * renderScale,
        format: px.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 100,
      );
      
      if (pageImage == null) {
        debugPrint('[PDF_ML] ERROR: pageImage is null');
        return _fallbackResult();
      }
      
      debugPrint('[PDF_ML] Rendered: '
          '${pageImage.width}x${pageImage.height} '
          '${pageImage.bytes.length} bytes');

      if (pageImage.bytes.length < 50000) {
        debugPrint('[PDF_ML] WARNING: Image too small, '
            'likely blank render');
      }
      
      await page.close();
      await document.close();

      final bytes4x = pageImage.bytes;

      // Heavy work (4x decode + inference + mask) runs in a persistent worker
      // isolate to keep the UI smooth. If the worker is unavailable or errors,
      // fall back to decoding + parsing on this isolate (current behaviour).
      try {
        final result = await ParserWorker.instance.parse(
          bytes4x: bytes4x,
          rects: regionRects,
          mPerPoint: mPerPoint,
          pageWidthPt: pageWidthPt,
          pageText: pageText,
          hasEmbeddedScale: embeddedRatio != null,
          userLongFt: userLongFt,
          userShortFt: userShortFt,
        );
        debugPrint('[PDF_ML] Parsed via worker isolate');
        return result;
      } catch (e) {
        debugPrint('[PDF_ML] Worker isolate failed ($e) — parsing on main');
      }

      final decoded = img.decodeImage(bytes4x);
      debugPrint('[PDF_ML] Image decoded: ${decoded?.width}x${decoded?.height}');

      if (decoded == null) {
        debugPrint('[PDF_ML] ERROR: decoded image is null');
        return _fallbackResult();
      }

      return await parseDecodedImage(decoded, mPerPoint, pageWidthPt,
          pageText: pageText,
          hasEmbeddedScale: embeddedRatio != null,
          userLongFt: userLongFt,
          userShortFt: userShortFt,
          regionRects: regionRects);

    } catch (e, stackTrace) {
      debugPrint('[PDF_ML] FATAL ERROR: $e');
      debugPrint('[PDF_ML] Stack: $stackTrace');
      return _fallbackResult();
    }
  }

  static Future<Map<String, dynamic>> parseDecodedImage(
      img.Image decoded, double mPerPoint, double pageWidthPt,
      {String? pageText,
      bool hasEmbeddedScale = false,
      double? userLongFt,
      double? userShortFt,
      List<List<double>>? regionRects}) async {
    try {
      final roomCounts = <String, int>{};

      // Crop the inference image into the detected region rects (page
      // fractions). Same resolution as the full image, so the global pt/px
      // ratio below still applies to every region.
      final rects = (regionRects == null || regionRects.isEmpty)
          ? const [
              [0.0, 0.0, 1.0, 1.0]
            ]
          : regionRects;
      final regions = <img.Image>[];
      for (final r in rects) {
        // Whole page → reuse the decoded image directly (no extra copy).
        if (r[0] <= 0 && r[1] <= 0 && r[2] >= 1 && r[3] >= 1) {
          regions.add(decoded);
          continue;
        }
        final int x0 = (r[0] * decoded.width).floor().clamp(0, decoded.width - 1);
        final int y0 =
            (r[1] * decoded.height).floor().clamp(0, decoded.height - 1);
        final int x1 = (r[2] * decoded.width).ceil().clamp(1, decoded.width);
        final int y1 = (r[3] * decoded.height).ceil().clamp(1, decoded.height);
        regions.add(img.copyCrop(decoded,
            x: x0, y: y0, width: math.max(1, x1 - x0), height: math.max(1, y1 - y0)));
      }
      debugPrint('[PDF_ML] Image segmented into ${regions.length} regions');
      final bool single = regions.length == 1;
      final double ptPerPx = pageWidthPt / decoded.width.toDouble();

      // Run inference on every region up front. Bounding boxes are scale
      // independent, so they can be used to derive the scale (for plans with
      // no embedded 1:NN) before any area is converted to m².
      final perRegionDets = <List<Map<String, dynamic>>>[];
      for (int ri = 0; ri < regions.length; ri++) {
        debugPrint('[PDF_ML] Region ${ri + 1}/${regions.length}: '
            '${regions[ri].width}x${regions[ri].height}');
        perRegionDets.add(await _runInference(regions[ri]));
      }

      // ---- Footprint model: a single-region residential plan with no embedded
      // scale. Room masks under-cover the floor (corridors/gaps are unlabelled),
      // so report the building footprint (built-up area) instead, deriving the
      // scale from the overall dimensions printed on the drawing. ----
      if (single && !hasEmbeddedScale) {
        final dets = perRegionDets[0];
        if (dets.isNotEmpty) {
          double minX = double.infinity, minY = double.infinity;
          double maxX = 0, maxY = 0;
          for (final d in dets) {
            final b = List<double>.from(d['bbox'] as List);
            if (b[0] < minX) minX = b[0];
            if (b[1] < minY) minY = b[1];
            if (b[2] > maxX) maxX = b[2];
            if (b[3] > maxY) maxY = b[3];
          }
          final double longPt = math.max(maxX - minX, maxY - minY) * ptPerPx;
          final double shortPt = math.min(maxX - minX, maxY - minY) * ptPerPx;

          // Scale priority: user-entered dimensions > dimensions printed on
          // the drawing. If neither is available we can't size the plan.
          double? dimsMpp;
          if (userLongFt != null && userShortFt != null) {
            // The user told us the size — trust it. Only guard against a
            // degenerate (zero-area) footprint; do NOT apply the auto-detection
            // plausibility bound, or valid user input could bounce back as
            // "needs scale" and leave the estimate unfinished.
            if (longPt > 0 && shortPt > 0) {
              final double ul = math.max(userLongFt, userShortFt);
              final double us = math.min(userLongFt, userShortFt);
              dimsMpp =
                  ((ul * 0.3048 / longPt) + (us * 0.3048 / shortPt)) / 2;
            }
          } else if (pageText != null) {
            dimsMpp = _scaleFromDims(pageText, longPt, shortPt);
          }

          if (dimsMpp != null) {
            final m2PerPx2 = math.pow(ptPerPx * dimsMpp, 2).toDouble();
            final footM2 = (maxX - minX) *
                (maxY - minY) *
                m2PerPx2 *
                _residentialEfficiency;
            for (final d in dets) {
              final cls = d['className'] as String;
              if (_roomClasses.contains(cls)) {
                roomCounts[cls] = (roomCounts[cls] ?? 0) + 1;
              }
            }
            debugPrint('[PDF_ML] FOOTPRINT area=$footM2 '
                'scale=1:${(dimsMpp * 1000 / 0.3528).round()} '
                '${userLongFt != null ? "(user dims)" : "(auto dims)"}');
            return {
              'totalFloorArea': double.parse(footM2.toStringAsFixed(2)),
              'totalWallLength': 0.0,
              'floorCount': 1,
              'roomCounts': roomCounts,
              'confidence': userLongFt != null ? 0.9 : 0.7,
              'parserType': 'ml_pdf_ondevice',
            };
          }

          // No embedded scale, no usable printed dimensions, no user input yet
          // -> the drawing cannot be sized automatically. Ask the user.
          debugPrint('[PDF_ML] NEEDS_SCALE (no scale or overall dimensions)');
          return {
            'totalFloorArea': 0.0,
            'totalWallLength': 0.0,
            'floorCount': 1,
            'roomCounts': const <String, int>{},
            'confidence': 0.0,
            'parserType': 'ml_pdf_needs_scale',
          };
        }
        // No detections at all -> fall through to room-mask path.
      }

      // ---- Room-mask sum model: multi-region sheets (e.g. Costco) and single
      // floors that carry an embedded scale. ----
      final regionResults = <Map<String, dynamic>>[];
      for (int ri = 0; ri < regions.length; ri++) {
        final region = regions[ri];
        final dets = perRegionDets[ri];
        if (dets.isEmpty) continue;

        final roomDets =
            dets.where((d) => _roomClasses.contains(d['className'])).toList();
        final imageArea = region.width * region.height.toDouble();
        final filtered = roomDets
            .where((d) => (d['areaPx'] as double) / imageArea <= 0.70)
            .toList();
        final dedupedRooms = _containmentFilter(filtered);

        final bathroomCount =
            dedupedRooms.where((d) => d['className'] == 'bathroom').length;
        final totalConf =
            dedupedRooms.fold<double>(0, (s, d) => s + (d['conf'] as double));
        final wallDets = dets.where((d) => d['className'] == 'wall').toList();

        regionResults.add({
          'detections': dedupedRooms,
          'wallDetections': wallDets,
          'bathroomCount': bathroomCount,
          'totalConf': totalConf,
        });
        debugPrint('[PDF_SEG] Region $ri: ${dedupedRooms.length} rooms, '
            '$bathroomCount bathrooms, conf=${totalConf.toStringAsFixed(2)}');
      }

      // Sum every region that produced detections. The old "bathroom-only"
      // selection collapsed to a single column whenever a bathroom happened
      // not to be detected in the others (which varies with the on-device
      // render), throwing away most of the floor area. Naive column splitting
      // can't read per-column text to exclude title/schedule columns the way
      // the backend reference does, so we include all regions and accept a
      // little over-count rather than dropping real plan columns.
      final selectedRegions = regionResults;
      debugPrint('[PDF_SEG] Summing all ${regionResults.length} regions');

      double totalAreaM2 = 0;
      double totalWallLengthM = 0;
      final m2PerPx2 = math.pow(ptPerPx * mPerPoint, 2).toDouble();

      for (final regionData in selectedRegions) {
        final filtered =
            regionData['detections'] as List<Map<String, dynamic>>;
        for (final det in filtered) {
          totalAreaM2 += (det['areaPx'] as double) * m2PerPx2;
          final cls = det['className'] as String;
          roomCounts[cls] = (roomCounts[cls] ?? 0) + 1;
        }

        final wallDets =
            regionData['wallDetections'] as List<Map<String, dynamic>>;
        for (final wd in wallDets) {
          final bbox = wd['bbox'] as List;
          final lenPx = math.max((bbox[2] as double) - (bbox[0] as double),
              (bbox[3] as double) - (bbox[1] as double));
          totalWallLengthM += lenPx * ptPerPx * mPerPoint;
        }
      }

      debugPrint('[PDF_ML] totalAreaM2=$totalAreaM2 '
          'rooms=${roomCounts.values.fold(0, (a, b) => a + b)}');

      return {
        'totalFloorArea': double.parse(totalAreaM2.toStringAsFixed(2)),
        'totalWallLength': double.parse(totalWallLengthM.toStringAsFixed(2)),
        'floorCount': 1,
        'roomCounts': roomCounts,
        'confidence': hasEmbeddedScale ? 0.85 : 0.65,
        'parserType': 'ml_pdf_ondevice',
      };

    } catch (e, stackTrace) {
      debugPrint('[PDF_ML] FATAL ERROR: $e');
      debugPrint('[PDF_ML] Stack: $stackTrace');
      return _fallbackResult();
    }
  }

  // Extract protos as [32][128][128] float matrix
  // Generate binary mask for one detection. [masks32] is the ONNX proto output
  // batch (shape [32, P, P]); read directly to avoid an extra copy.
  static List<List<bool>> _generateMask(
      List<double> maskCoeffs,
      List masks32) {

    final int protoSize = (masks32[0] as List).length;

    final mask = List.generate(protoSize,
        (_) => List<double>.filled(protoSize, 0.0));

    for (int m = 0; m < 32; m++) {
      final coeff = maskCoeffs[m];
      final maskM = masks32[m] as List;
      for (int r = 0; r < protoSize; r++) {
        final protoRow = maskM[r] as List;
        final mRow = mask[r];
        for (int c = 0; c < protoSize; c++) {
          mRow[c] += coeff * (protoRow[c] as num).toDouble();
        }
      }
    }
    
    final binary = List.generate(protoSize, (r) =>
      List.generate(protoSize, (c) {
        final sigmoid = 1.0 / (1.0 + math.exp(-mask[r][c]));
        return sigmoid > 0.5;
      }));
    
    int trueCount = 0;
    for (int r = 0; r < protoSize; r++) {
      for (int c = 0; c < protoSize; c++) {
        if (binary[r][c]) trueCount++;
      }
    }
    debugPrint('[PDF_ML_MASK] truePixels=$trueCount '
        'of ${protoSize*protoSize} total');

    return binary;
  }
  
  // Count foreground pixels in mask within bbox
  static double _countMaskPixels(
      List<List<bool>> mask,
      double x1, double y1, double x2, double y2,
      double origW, double origH) {
    
    const int protoSize = 128;
    
    final double maxDim = math.max(origW, origH);
    final double activeProtoWidth = protoSize * (origW / maxDim);
    final double activeProtoHeight = protoSize * (origH / maxDim);

    final px1 = (x1 / origW * activeProtoWidth).floor().clamp(0, protoSize - 1);
    final py1 = (y1 / origH * activeProtoHeight).floor().clamp(0, protoSize - 1);
    final px2 = (x2 / origW * activeProtoWidth).ceil().clamp(0, protoSize);
    final py2 = (y2 / origH * activeProtoHeight).ceil().clamp(0, protoSize);
    
    int maskPixels = 0;
    for (int r = py1; r < py2; r++) {
      for (int c = px1; c < px2; c++) {
        if (mask[r][c]) maskPixels++;
      }
    }
    
    final double onePixelArea = (maxDim / protoSize) * (maxDim / protoSize);
    final double areaPx = maskPixels * onePixelArea;

    debugPrint('[PDF_ML_COUNT] maskPx=$maskPixels '
        'scaledPx=$areaPx '
        'bbox=$px1,$py1-$px2,$py2');

    return areaPx;
  }

  // Remove a larger room outline when it fully contains a smaller room of the
  // same class (or when it is a generic 'room' wrapping a labelled room),
  // which prevents double-counting overlapping detections. Port of the Python
  // reference (ml_pdf_parser.py) containment filter.
  static List<Map<String, dynamic>> _containmentFilter(
      List<Map<String, dynamic>> dets) {
    final s = List<Map<String, dynamic>>.from(dets)
      ..sort((a, b) =>
          (b['areaPx'] as double).compareTo(a['areaPx'] as double));
    final keep = List<bool>.filled(s.length, true);
    for (int i = 0; i < s.length; i++) {
      if (!keep[i] || !_roomClasses.contains(s[i]['className'])) continue;
      final a = List<double>.from(s[i]['bbox'] as List);
      for (int j = i + 1; j < s.length; j++) {
        if (!keep[j] || !_roomClasses.contains(s[j]['className'])) continue;
        final b = List<double>.from(s[j]['bbox'] as List);
        const double t = 30.0;
        if (a[0] - t <= b[0] &&
            a[1] - t <= b[1] &&
            a[2] + t >= b[2] &&
            a[3] + t >= b[3]) {
          if (s[i]['className'] == 'room' ||
              s[i]['className'] == s[j]['className']) {
            keep[i] = false;
            break;
          }
        }
      }
    }
    final out = <Map<String, dynamic>>[];
    for (int i = 0; i < s.length; i++) {
      if (keep[i]) out.add(s[i]);
    }
    return out;
  }

  static Map<String, dynamic> _fallbackResult() => {
    'totalFloorArea': 0.0,
    'totalWallLength': 0.0,
    'floorCount': 1,
    'roomCounts': <String, int>{},
    'confidence': 0.1,
    'parserType': 'ml_pdf_failed',
  };
}
