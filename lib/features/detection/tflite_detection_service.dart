import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteDetectionService {
  TfliteDetectionService({
    this.modelAsset = 'assets/edge_detection.tflite',
  });

  final String modelAsset;
  Interpreter? _interpreter;
  TfliteInputSpec? _inputSpec;
  TfliteOutputSpec? _outputSpec;

  bool get isLoaded => _interpreter != null;

  String? get modelSummary {
    final input = _inputSpec;
    final output = _outputSpec;
    if (input == null || output == null) {
      return null;
    }

    return 'input ${input.shape.join('x')} ${input.type.name}, '
        'output ${output.shape.join('x')} ${output.type.name}';
  }

  Future<void> load() async {
    final interpreter = await Interpreter.fromAsset(modelAsset);
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    _interpreter = interpreter;
    _inputSpec = TfliteInputSpec.fromTensor(inputTensor);
    _outputSpec = TfliteOutputSpec.fromTensor(outputTensor);
  }

  TfliteDetectionResult? run(Uint8List jpegBytes) {
    final interpreter = _interpreter;
    final inputSpec = _inputSpec;
    var outputSpec = _outputSpec;
    if (interpreter == null || inputSpec == null || outputSpec == null) {
      return null;
    }

    final image = img.decodeImage(jpegBytes);
    if (image == null) {
      return null;
    }

    final input = buildInputBuffer(image, inputSpec);
    final output = Uint8List(outputSpec.byteCount);
    interpreter.run(input, output);

    final outputTensor = interpreter.getOutputTensor(0);
    outputSpec = TfliteOutputSpec.fromTensor(outputTensor);
    _outputSpec = outputSpec;

    final scores = decodeOutputScores(output, outputSpec);
    return TfliteDetectionResult.fromScores(
      scores,
      inferenceMicros: interpreter.lastNativeInferenceDurationMicroSeconds,
    );
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _inputSpec = null;
    _outputSpec = null;
  }

  static Object buildInputBuffer(img.Image source, TfliteInputSpec spec) {
    final resized = img.copyResize(
      source,
      width: spec.width,
      height: spec.height,
      interpolation: img.Interpolation.linear,
    );
    final elementCount = spec.width * spec.height * spec.channels;

    switch (spec.type) {
      case TensorType.float32:
        final values = Float32List(elementCount);
        _fillImageValues(
          resized: resized,
          channels: spec.channels,
          writeValue: (index, rawChannelValue) {
            values[index] = rawChannelValue / 255.0;
          },
        );
        return values.buffer;
      case TensorType.uint8:
        final values = Uint8List(elementCount);
        _fillImageValues(
          resized: resized,
          channels: spec.channels,
          writeValue: (index, rawChannelValue) {
            values[index] = _quantizeUint8(rawChannelValue, spec);
          },
        );
        return values;
      case TensorType.int8:
        final values = Uint8List(elementCount);
        final byteData = ByteData.view(values.buffer);
        _fillImageValues(
          resized: resized,
          channels: spec.channels,
          writeValue: (index, rawChannelValue) {
            byteData.setInt8(index, _quantizeInt8(rawChannelValue, spec));
          },
        );
        return values;
      default:
        throw UnsupportedError(
            'Input tensor type ${spec.type} is unsupported.');
    }
  }

  static List<double> decodeOutputScores(
    Uint8List outputBytes,
    TfliteOutputSpec spec,
  ) {
    final byteData = ByteData.view(outputBytes.buffer);
    final scores = <double>[];

    switch (spec.type) {
      case TensorType.float32:
        for (var offset = 0; offset < outputBytes.length; offset += 4) {
          scores.add(byteData.getFloat32(offset, Endian.little));
        }
        break;
      case TensorType.uint8:
        for (final value in outputBytes) {
          scores.add(_dequantize(value, spec.quantScale, spec.quantZeroPoint));
        }
        break;
      case TensorType.int8:
        for (var offset = 0; offset < outputBytes.length; offset++) {
          final value = byteData.getInt8(offset);
          scores.add(_dequantize(value, spec.quantScale, spec.quantZeroPoint));
        }
        break;
      case TensorType.int32:
        for (var offset = 0; offset < outputBytes.length; offset += 4) {
          scores.add(byteData.getInt32(offset, Endian.little).toDouble());
        }
        break;
      default:
        throw UnsupportedError(
          'Output tensor type ${spec.type} is unsupported.',
        );
    }

    return scores;
  }

  static void _fillImageValues({
    required img.Image resized,
    required int channels,
    required void Function(int index, int rawChannelValue) writeValue,
  }) {
    var index = 0;
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        if (channels == 1) {
          final gray =
              (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
          writeValue(index++, gray.clamp(0, 255).toInt());
        } else {
          writeValue(index++, pixel.r.toInt().clamp(0, 255).toInt());
          writeValue(index++, pixel.g.toInt().clamp(0, 255).toInt());
          writeValue(index++, pixel.b.toInt().clamp(0, 255).toInt());
        }
      }
    }
  }

  static int _quantizeUint8(int rawChannelValue, TfliteInputSpec spec) {
    if (spec.quantScale <= 0 || spec.quantScale >= 1) {
      return rawChannelValue.clamp(0, 255).toInt();
    }

    final normalized = rawChannelValue / 255.0;
    final quantized = (normalized / spec.quantScale + spec.quantZeroPoint)
        .round()
        .clamp(0, 255);
    return quantized.toInt();
  }

  static int _quantizeInt8(int rawChannelValue, TfliteInputSpec spec) {
    if (spec.quantScale <= 0) {
      return (rawChannelValue - 128).clamp(-128, 127).toInt();
    }

    final normalized = rawChannelValue / 255.0;
    final quantized = (normalized / spec.quantScale + spec.quantZeroPoint)
        .round()
        .clamp(-128, 127);
    return quantized.toInt();
  }

  static double _dequantize(int value, double scale, int zeroPoint) {
    if (scale <= 0) {
      return value.toDouble();
    }
    return scale * (value - zeroPoint);
  }
}

class TfliteInputSpec {
  const TfliteInputSpec({
    required this.shape,
    required this.type,
    required this.width,
    required this.height,
    required this.channels,
    required this.quantScale,
    required this.quantZeroPoint,
  });

  factory TfliteInputSpec.fromTensor(Tensor tensor) {
    final shape = tensor.shape;
    final type = tensor.type;
    final params = tensor.params;

    if (shape.length == 4) {
      final batch = shape[0] == -1 ? 1 : shape[0];
      if (batch != 1) {
        throw UnsupportedError('Only batch size 1 is supported: $shape');
      }
      return TfliteInputSpec(
        shape: shape,
        type: type,
        height: _validateDimension(shape[1], shape),
        width: _validateDimension(shape[2], shape),
        channels: _validateChannels(shape[3], shape),
        quantScale: params.scale,
        quantZeroPoint: params.zeroPoint,
      );
    }

    if (shape.length == 3) {
      return TfliteInputSpec(
        shape: shape,
        type: type,
        height: _validateDimension(shape[0], shape),
        width: _validateDimension(shape[1], shape),
        channels: _validateChannels(shape[2], shape),
        quantScale: params.scale,
        quantZeroPoint: params.zeroPoint,
      );
    }

    throw UnsupportedError('Unsupported input tensor shape: $shape');
  }

  final List<int> shape;
  final TensorType type;
  final int width;
  final int height;
  final int channels;
  final double quantScale;
  final int quantZeroPoint;

  int get elementCount => width * height * channels;

  static int _validateDimension(int dimension, List<int> shape) {
    if (dimension > 0) {
      return dimension;
    }
    throw UnsupportedError(
        'Dynamic input dimensions are not supported: $shape');
  }

  static int _validateChannels(int channels, List<int> shape) {
    if (channels == 1 || channels == 3) {
      return channels;
    }
    throw UnsupportedError('Unsupported input channel count $channels: $shape');
  }
}

class TfliteOutputSpec {
  const TfliteOutputSpec({
    required this.shape,
    required this.type,
    required this.byteCount,
    required this.quantScale,
    required this.quantZeroPoint,
  });

  factory TfliteOutputSpec.fromTensor(Tensor tensor) {
    final params = tensor.params;
    return TfliteOutputSpec(
      shape: tensor.shape,
      type: tensor.type,
      byteCount: tensor.numBytes(),
      quantScale: params.scale,
      quantZeroPoint: params.zeroPoint,
    );
  }

  final List<int> shape;
  final TensorType type;
  final int byteCount;
  final double quantScale;
  final int quantZeroPoint;
}

class TfliteDetectionResult {
  const TfliteDetectionResult({
    required this.maxScore,
    required this.meanScore,
    required this.activeRatio,
    required this.inferenceMicros,
  });

  factory TfliteDetectionResult.fromScores(
    List<double> rawScores, {
    required int inferenceMicros,
  }) {
    if (rawScores.isEmpty) {
      return TfliteDetectionResult(
        maxScore: 0,
        meanScore: 0,
        activeRatio: 0,
        inferenceMicros: inferenceMicros,
      );
    }

    var maxScore = 0.0;
    var sum = 0.0;
    var active = 0;

    for (final rawScore in rawScores) {
      final score = _normalizeScore(rawScore);
      maxScore = math.max(maxScore, score);
      sum += score;
      if (score >= 0.5) {
        active++;
      }
    }

    return TfliteDetectionResult(
      maxScore: maxScore,
      meanScore: sum / rawScores.length,
      activeRatio: active / rawScores.length,
      inferenceMicros: inferenceMicros,
    );
  }

  final double maxScore;
  final double meanScore;
  final double activeRatio;
  final int inferenceMicros;

  String get compactLabel {
    final activePercent = (activeRatio * 100).toStringAsFixed(1);
    final maxPercent = (maxScore * 100).toStringAsFixed(0);
    final inferenceMs = (inferenceMicros / 1000).toStringAsFixed(1);
    return 'IA ativa $activePercent% | pico $maxPercent% | ${inferenceMs}ms';
  }

  static double _normalizeScore(double score) {
    if (!score.isFinite) {
      return 0;
    }
    if (score >= 0 && score <= 1) {
      return score;
    }
    if (score >= 0 && score <= 255) {
      return score / 255.0;
    }
    return score.clamp(0, 1).toDouble();
  }
}
