import 'dart:typed_data';

import 'package:vazamento_detector/features/detection/tflite_detection_service.dart';
import 'package:vazamento_detector/features/processing/image_processor.dart';

class InspectionResult {
  const InspectionResult({
    required this.imageBytes,
    required this.visualAnalysis,
    required this.aiStatus,
    required this.createdAt,
    this.aiResult,
    this.aiErrorDetail,
  });

  final Uint8List imageBytes;
  final ImageAnalysisResult visualAnalysis;
  final TfliteDetectionResult? aiResult;
  final String aiStatus;
  final String? aiErrorDetail;
  final DateTime createdAt;

  bool get hasAiError => aiErrorDetail != null && aiErrorDetail!.isNotEmpty;
}
