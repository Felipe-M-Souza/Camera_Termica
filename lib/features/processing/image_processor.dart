import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class FilterOptions {
  const FilterOptions({
    this.simulatedThermal = false,
    this.edgeHighlight = false,
    this.contrastBoost = false,
    this.lowLightView = false,
    this.simulatedUv = false,
    this.suspiciousDarkAreaHighlight = false,
  });

  final bool simulatedThermal;
  final bool edgeHighlight;
  final bool contrastBoost;
  final bool lowLightView;
  final bool simulatedUv;
  final bool suspiciousDarkAreaHighlight;

  FilterOptions copyWith({
    bool? simulatedThermal,
    bool? edgeHighlight,
    bool? contrastBoost,
    bool? lowLightView,
    bool? simulatedUv,
    bool? suspiciousDarkAreaHighlight,
  }) {
    return FilterOptions(
      simulatedThermal: simulatedThermal ?? this.simulatedThermal,
      edgeHighlight: edgeHighlight ?? this.edgeHighlight,
      contrastBoost: contrastBoost ?? this.contrastBoost,
      lowLightView: lowLightView ?? this.lowLightView,
      simulatedUv: simulatedUv ?? this.simulatedUv,
      suspiciousDarkAreaHighlight:
          suspiciousDarkAreaHighlight ?? this.suspiciousDarkAreaHighlight,
    );
  }
}

class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.planes,
  });

  factory CameraFrame.fromCameraImage(CameraImage image) {
    return CameraFrame(
      width: image.width,
      height: image.height,
      planes: image.planes
          .map(
            (plane) => CameraFramePlane(
              bytes: Uint8List.fromList(plane.bytes),
              bytesPerRow: plane.bytesPerRow,
              bytesPerPixel: plane.bytesPerPixel ?? 1,
            ),
          )
          .toList(growable: false),
    );
  }

  final int width;
  final int height;
  final List<CameraFramePlane> planes;
}

class CameraFramePlane {
  const CameraFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class ProcessImageRequest {
  const ProcessImageRequest({
    required this.frame,
    required this.filters,
  });

  final CameraFrame frame;
  final FilterOptions filters;
}

class ProcessedFrame {
  const ProcessedFrame({
    required this.jpegBytes,
    required this.originalJpegBytes,
    required this.analysis,
  });

  final Uint8List jpegBytes;
  final Uint8List originalJpegBytes;
  final ImageAnalysisResult analysis;
}

class ImageAnalysisResult {
  const ImageAnalysisResult({
    required this.redSignalPixels,
    required this.hotColorPixels,
    required this.darkAreaPixels,
  });

  final int redSignalPixels;
  final int hotColorPixels;
  final int darkAreaPixels;

  bool get hasSuspiciousVisualSignal =>
      redSignalPixels > 50 || hotColorPixels > 50 || darkAreaPixels > 80;

  String? get message {
    if (redSignalPixels > 50) {
      return 'Possivel rachadura ou marca avermelhada detectada';
    }
    if (hotColorPixels > 50) {
      return 'Area com cor quente visualmente destacada';
    }
    if (darkAreaPixels > 80) {
      return 'Area escura suspeita detectada';
    }
    return null;
  }
}

ProcessedFrame processImageFrame(ProcessImageRequest request) {
  return ImageProcessor.process(request);
}

class ImageProcessor {
  const ImageProcessor._();

  static ProcessedFrame process(ProcessImageRequest request) {
    final originalImage = convertYuv420ToImage(request.frame);
    final analysis = analyzeImage(originalImage);
    var displayImage = img.Image.from(originalImage);

    if (request.filters.edgeHighlight) {
      displayImage = img.sobel(displayImage);
    }

    if (request.filters.contrastBoost) {
      displayImage = img.adjustColor(displayImage, contrast: 150);
    }

    if (request.filters.simulatedThermal) {
      displayImage = applySimulatedThermalFilter(displayImage);
    }

    if (request.filters.lowLightView) {
      displayImage = applyLowLightFilter(displayImage);
    }

    if (request.filters.simulatedUv) {
      displayImage = applySimulatedUvFilter(displayImage);
    }

    if (request.filters.suspiciousDarkAreaHighlight) {
      displayImage = highlightSuspiciousDarkAreas(displayImage);
    }

    return ProcessedFrame(
      jpegBytes: Uint8List.fromList(img.encodeJpg(displayImage, quality: 55)),
      originalJpegBytes:
          Uint8List.fromList(img.encodeJpg(originalImage, quality: 75)),
      analysis: analysis,
    );
  }

  static ImageAnalysisResult analyzeImage(img.Image image) {
    var redSignalPixels = 0;
    var hotColorPixels = 0;
    var darkAreaPixels = 0;

    for (var y = 1; y < image.height - 1; y++) {
      for (var x = 1; x < image.width - 1; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        final brightness = 0.299 * r + 0.587 * g + 0.114 * b;

        if (r > 180 && g < 80 && b < 80) {
          redSignalPixels++;
        }

        if ((r > 200 && g > 100 && b < 100) ||
            (r > 200 && g < 100 && b < 100)) {
          hotColorPixels++;
        }

        if (brightness < 45) {
          darkAreaPixels++;
        }
      }
    }

    return ImageAnalysisResult(
      redSignalPixels: redSignalPixels,
      hotColorPixels: hotColorPixels,
      darkAreaPixels: darkAreaPixels,
    );
  }

  static img.Image convertYuv420ToImage(CameraFrame frame) {
    if (frame.planes.length < 3) {
      throw ArgumentError('YUV420 frame must contain three planes.');
    }

    final image = img.Image(width: frame.width, height: frame.height);
    final planeY = frame.planes[0];
    final planeU = frame.planes[1];
    final planeV = frame.planes[2];

    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final indexY = y * planeY.bytesPerRow + x;
        final uvRow = y ~/ 2;
        final uvCol = x ~/ 2;
        final indexU =
            uvRow * planeU.bytesPerRow + uvCol * planeU.bytesPerPixel;
        final indexV =
            uvRow * planeV.bytesPerRow + uvCol * planeV.bytesPerPixel;

        final yValue = planeY.bytes[indexY];
        final uValue = planeU.bytes[indexU];
        final vValue = planeV.bytes[indexV];

        var red = (yValue + 1.370705 * (vValue - 128)).round();
        var green =
            (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
                .round();
        var blue = (yValue + 1.732446 * (uValue - 128)).round();

        red = red.clamp(0, 255).toInt();
        green = green.clamp(0, 255).toInt();
        blue = blue.clamp(0, 255).toInt();

        image.setPixel(x, y, img.ColorRgb8(red, green, blue));
      }
    }

    return image;
  }

  static img.Image applySimulatedThermalFilter(img.Image src) {
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final intensity = pixel.r.toInt();
        src.setPixel(
          x,
          y,
          img.ColorRgb8(intensity, 255 - intensity, intensity ~/ 2),
        );
      }
    }
    return src;
  }

  static img.Image applyLowLightFilter(img.Image src) {
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final avg = ((pixel.r + pixel.g + pixel.b) ~/ 3).clamp(0, 255);
        src.setPixel(x, y, img.ColorRgb8(0, avg.toInt(), 0));
      }
    }
    return src;
  }

  static img.Image applySimulatedUvFilter(img.Image src) {
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final red = (pixel.r * 1.2).clamp(0, 255).toInt();
        final green = (pixel.g * 0.6).clamp(0, 255).toInt();
        final blue = (pixel.b * 1.5).clamp(0, 255).toInt();
        src.setPixel(x, y, img.ColorRgb8(red, green, blue));
      }
    }
    return src;
  }

  static img.Image highlightSuspiciousDarkAreas(img.Image src) {
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        if (brightness < 50) {
          src.setPixel(x, y, img.ColorRgb8(255, 0, 0));
        }
      }
    }
    return src;
  }
}
