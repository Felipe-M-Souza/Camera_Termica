import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vazamento_detector/features/detection/tflite_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset tflite esta declarado no bundle', () async {
    final modelBytes = await rootBundle.load('assets/edge_detection.tflite');

    expect(modelBytes.lengthInBytes, greaterThan(0));
  });

  test('prepara input float32 RGB normalizado', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixel(0, 0, img.ColorRgb8(255, 128, 0));
    const spec = TfliteInputSpec(
      shape: [1, 1, 1, 3],
      type: TensorType.float32,
      width: 1,
      height: 1,
      channels: 3,
      quantScale: 0,
      quantZeroPoint: 0,
    );

    final buffer = TfliteDetectionService.buildInputBuffer(image, spec);
    final values = Float32List.view((buffer as ByteBuffer));

    expect(values.length, 3);
    expect(values[0], closeTo(1, 0.001));
    expect(values[1], closeTo(128 / 255, 0.001));
    expect(values[2], closeTo(0, 0.001));
  });

  test('prepara input uint8 em tons de cinza', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixel(0, 0, img.ColorRgb8(10, 20, 30));
    const spec = TfliteInputSpec(
      shape: [1, 1, 1, 1],
      type: TensorType.uint8,
      width: 1,
      height: 1,
      channels: 1,
      quantScale: 0,
      quantZeroPoint: 0,
    );

    final values =
        TfliteDetectionService.buildInputBuffer(image, spec) as Uint8List;

    expect(values.length, 1);
    expect(values.single, 18);
  });

  test('resume scores de saida em percentuais normalizados', () {
    final result = TfliteDetectionResult.fromScores(
      [0, 0.25, 128, 255],
      inferenceMicros: 2000,
    );

    expect(result.maxScore, closeTo(1, 0.001));
    expect(result.meanScore, closeTo(0.438, 0.001));
    expect(result.activeRatio, closeTo(0.5, 0.001));
    expect(result.compactLabel, contains('2.0ms'));
  });
}
