import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vazamento_detector/features/processing/image_processor.dart';

void main() {
  test('detecta areas escuras suspeitas na imagem original', () {
    final image = _solidImage(
      width: 12,
      height: 12,
      color: img.ColorRgb8(12, 12, 12),
    );

    final result = ImageProcessor.analyzeImage(image);

    expect(result.darkAreaPixels, greaterThan(80));
    expect(result.hasSuspiciousVisualSignal, isTrue);
    expect(result.message, contains('Area escura'));
  });

  test('detecta marcas avermelhadas visiveis', () {
    final image = _solidImage(
      width: 12,
      height: 12,
      color: img.ColorRgb8(220, 20, 20),
    );

    final result = ImageProcessor.analyzeImage(image);

    expect(result.redSignalPixels, greaterThan(50));
    expect(result.hasSuspiciousVisualSignal, isTrue);
  });

  test('filtro termico simulado altera apenas a visualizacao', () {
    final image = _solidImage(
      width: 4,
      height: 4,
      color: img.ColorRgb8(100, 150, 200),
    );

    final originalBeforeFilter = img.Image.from(image);
    final filtered = ImageProcessor.applySimulatedThermalFilter(image);

    expect(
      filtered.getPixel(0, 0).g,
      isNot(originalBeforeFilter.getPixel(0, 0).g),
    );
  });
}

img.Image _solidImage({
  required int width,
  required int height,
  required img.Color color,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(x, y, color);
    }
  }
  return image;
}
