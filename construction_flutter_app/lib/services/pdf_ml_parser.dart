import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:flutter/foundation.dart';

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

  // Detect scale from PDF text
  static Future<double> _detectScale(String pdfPath, {int pageIndex = 0}) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      
      final extractor = sf.PdfTextExtractor(document);
      final text = extractor.extractText(
          startPageIndex: pageIndex, endPageIndex: pageIndex);
      document.dispose();
      
      // Search for scale patterns like 1:50, 1:100, 1:75
      final regex = RegExp(r'1[:/](\d+)');
      final match = regex.firstMatch(text);
      if (match != null) {
        final ratio = int.tryParse(match.group(1) ?? '');
        if (ratio != null && ratio >= 20 && ratio <= 500) {
          // 1pt = 0.3528mm paper
          // at 1:ratio → 1pt = 0.3528 * ratio mm real
          return (0.3528 * ratio) / 1000.0;
        }
      }
    } catch (e) {
      debugPrint('Scale detection failed: $e');
    }
    // Default: 1:75 for Indian residential
    return (0.3528 * 75) / 1000.0;
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
    
    final protosData = outputs[1]!.value;
    final protos = _extractProtos(protosData);
    
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
      final mask = _generateMask(maskCoeffs, protos);
      
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

  static Future<List<img.Image>> _segmentImage(
      img.Image image) {
    
    // Single page floor plan - no splitting needed
    if (image.width <= 6000) {
      return Future.value([image]);
    }
    
    // Multi-view sheet - split into regions
    // Simple approach: split into equal columns
    // based on width
    final regions = <img.Image>[];
    
    // Detect number of columns based on width
    int numCols = 2;
    if (image.width > 8000) numCols = 3;
    if (image.width > 12000) numCols = 4;
    
    final colWidth = image.width ~/ numCols;
    
    for (int i = 0; i < numCols; i++) {
      final x = i * colWidth;
      final w = (i == numCols - 1) 
          ? image.width - x  // last column gets remainder
          : colWidth;
      
      final region = img.copyCrop(
          image, x: x, y: 0, width: w, height: image.height);
      regions.add(region);
    }
    
    return Future.value(regions);
  }

  // Main entry point
  static Future<Map<String, dynamic>> parsePdf(
      String pdfPath) async {
    try {
      debugPrint('[PDF_ML] Starting parsePdf: $pdfPath');
      
      final bytes = await File(pdfPath).readAsBytes();
      final sfDoc = sf.PdfDocument(inputBytes: bytes);
      final bestPageIndex = await _selectBestPage(sfDoc, pdfPath);
      sfDoc.dispose();
      
      final mPerPoint = await _detectScale(pdfPath, pageIndex: bestPageIndex);
      debugPrint('[PDF_ML] Scale detected: $mPerPoint');
      
      final document = await px.PdfDocument.openFile(pdfPath);
      debugPrint('[PDF_ML] Document opened, pages: ${document.pagesCount}');
      
      final page = await document.getPage(bestPageIndex + 1);
      final double pageWidthPt = page.width;
      debugPrint('[PDF_ML] Page opened: ${page.width}x${page.height}');
      
      final pageImage = await page.render(
        width: page.width * 4,   // 4x instead of 2x (double type)
        height: page.height * 4, // 4x instead of 2x (double type)
        format: px.PdfPageImageFormat.jpeg,   // JPEG instead of PNG
        backgroundColor: '#FFFFFF',        // explicit white background
        quality: 100,                      // maximum quality
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
      
      final decoded = img.decodeImage(pageImage.bytes);
      debugPrint('[PDF_ML] Image decoded: ${decoded?.width}x${decoded?.height}');
      
      if (decoded == null) {
        debugPrint('[PDF_ML] ERROR: decoded image is null');
        return _fallbackResult();
      }
      
      return await parseDecodedImage(decoded, mPerPoint, pageWidthPt);
      
    } catch (e, stackTrace) {
      debugPrint('[PDF_ML] FATAL ERROR: $e');
      debugPrint('[PDF_ML] Stack: $stackTrace');
      return _fallbackResult();
    }
  }

  static Future<Map<String, dynamic>> parseDecodedImage(
      img.Image decoded, double mPerPoint, double pageWidthPt) async {
    try {
      final roomCounts = <String, int>{};
    final roomBreakdown = <Map<String, dynamic>>[];

    final regions = await _segmentImage(decoded);
    debugPrint('[PDF_ML] Image segmented into ${regions.length} regions');
    
    final regionResults = <Map<String, dynamic>>[];
    
    for (int ri = 0; ri < regions.length; ri++) {
      final region = regions[ri];
      debugPrint('[PDF_ML] Processing region ${ri + 1}/${regions.length}: ${region.width}x${region.height}');
      final dets = await _runInference(region);
      
      if (dets.isEmpty) continue;
      
      final roomDets = dets.where(
          (d) => _roomClasses.contains(d['className'])).toList();
      
      // Apply absolute void filter
      final imageArea = region.width * region.height.toDouble();
      final filtered = roomDets.where(
          (d) => (d['areaPx'] as double) / imageArea <= 0.70)
          .toList();
      
      List<Map<String, dynamic>> removeOverlapping(List<Map<String, dynamic>> dets) {
        if (dets.length <= 1) return dets;
        
        final sorted = List<Map<String, dynamic>>.from(dets)
          ..sort((a, b) => (b['areaPx'] as double).compareTo(a['areaPx'] as double));
        
        final kept = <Map<String, dynamic>>[];
        for (final det in sorted) {
          bool dominated = false;
          final bbox = List<double>.from(det['bbox'] as List);
          
          for (final other in kept) {
            final obbox = List<double>.from(other['bbox'] as List);
            // Calculate intersection over smaller bbox
            final ix1 = math.max(bbox[0], obbox[0]);
            final iy1 = math.max(bbox[1], obbox[1]);
            final ix2 = math.min(bbox[2], obbox[2]);
            final iy2 = math.min(bbox[3], obbox[3]);
            
            if (ix2 > ix1 && iy2 > iy1) {
              final inter = (ix2 - ix1) * (iy2 - iy1);
              final detArea = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]);
              final overlapRatio = inter / detArea;
              
              // If this detection is 40%+ overlapped with a larger kept detection, skip it
              if (overlapRatio > 0.40) {
                dominated = true;
                break;
              }
            }
          }
          if (!dominated) kept.add(det);
        }
        return kept;
      }

      final dedupedRooms = removeOverlapping(filtered);
      
      final bathroomCount = dedupedRooms.where(
          (d) => d['className'] == 'bathroom').length;
      final totalConf = dedupedRooms.fold<double>(
          0, (s, d) => s + (d['conf'] as double));
      final totalArea = dedupedRooms.fold<double>(
          0, (s, d) => s + (d['areaPx'] as double));
      
      final wallDets = dets.where(
          (d) => d['className'] == 'wall').toList();
      
      regionResults.add({
        'regionIndex': ri,
        'detections': dedupedRooms,
        'wallDetections': wallDets,
        'bathroomCount': bathroomCount,
        'totalConf': totalConf,
        'totalArea': totalArea,
      });
      
      debugPrint('[PDF_SEG] Region $ri: '
          '${dedupedRooms.length} rooms, '
          '${bathroomCount} bathrooms, '
          'conf=${totalConf.toStringAsFixed(2)}');
    }
    
    // For multi-region sheets: if any region has bathrooms,
    // only use regions with bathrooms.
    // For single region: use it directly.
    List<Map<String, dynamic>> selectedRegions;
    
    if (regions.length == 1) {
      selectedRegions = regionResults;
    } else {
      final bathroomRegions = regionResults.where(
          (r) => (r['bathroomCount'] as int) > 0).toList();
      
      if (bathroomRegions.isNotEmpty) {
        // Use only bathroom-containing regions
        selectedRegions = bathroomRegions;
        debugPrint('[PDF_SEG] Using ${bathroomRegions.length} '
            'bathroom regions out of ${regionResults.length}');
      } else {
        // No bathroom regions — use region with highest confidence
        regionResults.sort((a, b) =>
            (b['totalConf'] as double)
            .compareTo(a['totalConf'] as double));
        selectedRegions = regionResults.isNotEmpty 
            ? [regionResults.first] : [];
        debugPrint('[PDF_SEG] No bathrooms found, '
            'using highest-confidence region');
      }
    }
    
    // Sum area from selected regions only
    double totalAreaM2 = 0;
    double totalWallLengthM = 0;
    final allRoomDets = <Map<String, dynamic>>[];
    
    final ptPerPx = (pageWidthPt / decoded.width.toDouble());
    final m2PerPx2 = math.pow(ptPerPx * mPerPoint, 2).toDouble();
    
    for (final regionData in selectedRegions) {
      final filtered = regionData['detections'] 
          as List<Map<String, dynamic>>;
      
      for (final det in filtered) {
        final areaM2 = (det['areaPx'] as double) * m2PerPx2;
        totalAreaM2 += areaM2;
        allRoomDets.add(det);
        final cls = det['className'] as String;
        roomCounts[cls] = (roomCounts[cls] ?? 0) + 1;
      }
      
      final wallDets = regionData['wallDetections']
          as List<Map<String, dynamic>>;
      for (final wd in wallDets) {
        final bbox = wd['bbox'] as List;
        final double bx1 = bbox[0] as double;
        final double by1 = bbox[1] as double;
        final double bx2 = bbox[2] as double;
        final double by2 = bbox[3] as double;
        final lenPx = math.max(bx2 - bx1, by2 - by1);
        totalWallLengthM += lenPx * ptPerPx * mPerPoint;
      }
    }
    
    debugPrint('[PDF_ML] totalAreaM2=$totalAreaM2 '
        'roomDetections=${allRoomDets.length} '
        'm2PerPx2=${math.pow((pageWidthPt / decoded.width.toDouble()) * mPerPoint, 2).toDouble()}');

    final hasScale = mPerPoint != (0.3528 * 75) / 1000.0;
    
    return {
      'totalFloorArea': double.parse(totalAreaM2.toStringAsFixed(2)),
      'totalWallLength': double.parse(totalWallLengthM.toStringAsFixed(2)),
      'floorCount': 1,
      'roomCounts': roomCounts,
      'confidence': hasScale ? 0.85 : 0.65,
      'parserType': 'ml_pdf_ondevice',
    };
      
    } catch (e, stackTrace) {
      debugPrint('[PDF_ML] FATAL ERROR: $e');
      debugPrint('[PDF_ML] Stack: $stackTrace');
      return _fallbackResult();
    }
  }

  // Extract protos as [32][128][128] float matrix
  static List<List<List<double>>> _extractProtos(
      dynamic protosOutput) {
    final batch = protosOutput as List;
    final masks32 = batch[0] as List;  // 32 prototype masks
    
    final protos = <List<List<double>>>[];
    for (int m = 0; m < 32; m++) {
      final mask = masks32[m] as List;  // 128 rows
      final rows = <List<double>>[];
      for (int r = 0; r < 128; r++) {
        final row = mask[r] as List;  // 128 cols
        rows.add(row.map((v) => (v as num).toDouble()).toList());
      }
      protos.add(rows);
    }
    return protos;
  }
  
  // Generate binary mask for one detection
  static List<List<bool>> _generateMask(
      List<double> maskCoeffs,
      List<List<List<double>>> protos) {
    
    const int protoSize = 128;
    
    final mask = List.generate(protoSize,
        (_) => List<double>.filled(protoSize, 0.0));
    
    for (int m = 0; m < 32; m++) {
      final coeff = maskCoeffs[m];
      for (int r = 0; r < protoSize; r++) {
        for (int c = 0; c < protoSize; c++) {
          mask[r][c] += coeff * protos[m][r][c];
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

  static Map<String, dynamic> _fallbackResult() => {
    'totalFloorArea': 0.0,
    'totalWallLength': 0.0,
    'floorCount': 1,
    'roomCounts': <String, int>{},
    'confidence': 0.1,
    'parserType': 'ml_pdf_failed',
  };
}
