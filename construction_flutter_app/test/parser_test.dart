import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:construction_app/services/pdf_ml_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Costco PDF pre-rendered PNG parsing test', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    
    // Load local ONNX model
    final modelBytes = File('assets/models/best.onnx').readAsBytesSync();
    final session = OrtSession.fromBuffer(modelBytes, sessionOptions);
    PdfMlParser.session = session;
    
    // Load pre-rendered Costco PNG
    final pngPath = 'c:/Users/sukhs/OneDrive/Documents/8th_Sem_Project/Pdf plans/00-6030-08 Costco 531 S Mississauga, ON - Washroom Remodel -Architectural (1).png';
    print('Loading PNG from: $pngPath');
    final pngBytes = File(pngPath).readAsBytesSync();
    final decoded = img.decodeImage(pngBytes);
    
    if (decoded == null) {
      fail('Failed to decode Costco PNG');
    }
    
    print('Decoded image size: ${decoded.width}x${decoded.height}');
    
    // Run the parsed image logic using the detected page width (3024.0) and scale (0.02646)
    final result = await PdfMlParser.parseDecodedImage(decoded, 0.02646, 3024.0);
    print('Parsing Result: $result');
    
    session.release();
    OrtEnv.instance.release();
  });
}
