import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vazamento_detector/features/inspection/inspection_result.dart';
import 'package:vazamento_detector/features/processing/image_processor.dart';

void main() {
  test('indica erro de IA quando detalhe esta presente', () {
    final result = InspectionResult(
      imageBytes: Uint8List(1),
      visualAnalysis: const ImageAnalysisResult(
        redSignalPixels: 0,
        hotColorPixels: 0,
        darkAreaPixels: 0,
      ),
      aiStatus: 'IA indisponivel',
      aiErrorDetail: 'modelo incompativel',
      createdAt: DateTime(2026),
    );

    expect(result.hasAiError, isTrue);
  });
}
