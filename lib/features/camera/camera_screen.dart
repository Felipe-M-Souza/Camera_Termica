import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vazamento_detector/features/detection/tflite_detection_service.dart';
import 'package:vazamento_detector/features/processing/image_processor.dart';

enum _FilterAction {
  simulatedThermal,
  edgeHighlight,
  contrastBoost,
  lowLightView,
  simulatedUv,
  suspiciousDarkAreaHighlight,
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    required this.onThemeToggle,
    super.key,
  });

  final VoidCallback onThemeToggle;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final TfliteDetectionService _detectionService = TfliteDetectionService();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selectedCamera;
  Uint8List? _processedImage;
  TfliteDetectionResult? _tfliteResult;
  FilterOptions _filters = const FilterOptions();
  ResolutionPreset _selectedResolution = ResolutionPreset.medium;
  DateTime _lastProcessTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastInferenceTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _aiStatus = 'Carregando IA...';
  String? _errorMessage;
  var _isInitializing = true;
  var _isProcessing = false;
  var _isRunningInference = false;
  var _alreadyShownToast = false;
  var _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadTfliteModel());
    unawaited(_setupCamera());
  }

  Future<void> _loadTfliteModel() async {
    try {
      await _detectionService.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _aiStatus = 'IA pronta (${_detectionService.modelSummary})';
      });
    } catch (error, stackTrace) {
      debugPrint('Erro ao carregar modelo TFLite: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _aiStatus = 'IA indisponivel';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeController());
      return;
    }

    if (state == AppLifecycleState.resumed && _selectedCamera != null) {
      unawaited(_initializeController(_selectedCamera!));
    }
  }

  Future<void> _setupCamera() async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });
    }

    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Permissao de camera negada.';
        });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Nenhuma camera foi encontrada neste dispositivo.';
        });
        return;
      }

      final preferredCamera = _selectedCamera ?? _findBackCamera(cameras);
      if (!mounted) {
        return;
      }

      setState(() {
        _cameras = cameras;
        _selectedCamera = preferredCamera;
      });

      await _initializeController(preferredCamera);
    } catch (error, stackTrace) {
      debugPrint('Erro ao preparar camera: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Nao foi possivel iniciar a camera.';
      });
    }
  }

  CameraDescription _findBackCamera(List<CameraDescription> cameras) {
    return cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
  }

  Future<void> _initializeController(CameraDescription camera) async {
    final generation = ++_cameraGeneration;
    setState(() {
      _isInitializing = true;
      _processedImage = null;
      _errorMessage = null;
    });

    await _disposeController();

    final controller = CameraController(
      camera,
      _selectedResolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _cameraController = controller;

    try {
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      await controller.startImageStream(_onCameraImage);
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      setState(() {
        _isInitializing = false;
        _selectedCamera = camera;
      });
    } catch (error, stackTrace) {
      debugPrint('Erro ao inicializar camera: $error');
      debugPrintStack(stackTrace: stackTrace);
      await controller.dispose();
      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Falha ao abrir a camera selecionada.';
      });
    }
  }

  void _onCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (_isProcessing ||
        now.difference(_lastProcessTime).inMilliseconds < 300) {
      return;
    }

    _lastProcessTime = now;
    _isProcessing = true;

    final request = ProcessImageRequest(
      frame: CameraFrame.fromCameraImage(image),
      filters: _filters,
    );
    unawaited(_processCameraImage(request));
  }

  Future<void> _processCameraImage(ProcessImageRequest request) async {
    try {
      final result = await compute(processImageFrame, request);
      if (!mounted) {
        return;
      }

      _showAnalysisToast(result.analysis);
      setState(() {
        _processedImage = result.jpegBytes;
      });
      unawaited(_maybeRunTflite(result.originalJpegBytes));
    } catch (error, stackTrace) {
      debugPrint('Erro no processamento de imagem: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _maybeRunTflite(Uint8List originalJpegBytes) async {
    final now = DateTime.now();
    if (!_detectionService.isLoaded ||
        _isRunningInference ||
        now.difference(_lastInferenceTime).inMilliseconds < 1000) {
      return;
    }

    _lastInferenceTime = now;
    setState(() {
      _isRunningInference = true;
    });
    try {
      final result = _detectionService.run(originalJpegBytes);
      if (!mounted || result == null) {
        return;
      }
      setState(() {
        _tfliteResult = result;
        _aiStatus = result.compactLabel;
      });
    } catch (error, stackTrace) {
      debugPrint('Erro na inferencia TFLite: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _aiStatus = 'Erro na IA';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunningInference = false;
        });
      } else {
        _isRunningInference = false;
      }
    }
  }

  void _showAnalysisToast(ImageAnalysisResult analysis) {
    final message = analysis.message;
    if (_alreadyShownToast || message == null) {
      return;
    }

    _alreadyShownToast = true;
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );

    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), () {
        _alreadyShownToast = false;
      }),
    );
  }

  Future<void> _changeResolution(ResolutionPreset resolution) async {
    if (resolution == _selectedResolution) {
      return;
    }

    setState(() {
      _selectedResolution = resolution;
    });

    final camera = _selectedCamera;
    if (camera != null) {
      await _initializeController(camera);
    }
  }

  Future<void> _cycleCamera() async {
    if (_cameras.length < 2) {
      return;
    }

    final currentIndex = _cameras.indexOf(_selectedCamera ?? _cameras.first);
    final nextCamera = _cameras[(currentIndex + 1) % _cameras.length];
    await _initializeController(nextCamera);
  }

  void _toggleFilter(_FilterAction action) {
    setState(() {
      switch (action) {
        case _FilterAction.simulatedThermal:
          _filters = _filters.copyWith(
            simulatedThermal: !_filters.simulatedThermal,
          );
          break;
        case _FilterAction.edgeHighlight:
          _filters = _filters.copyWith(
            edgeHighlight: !_filters.edgeHighlight,
          );
          break;
        case _FilterAction.contrastBoost:
          _filters = _filters.copyWith(
            contrastBoost: !_filters.contrastBoost,
          );
          break;
        case _FilterAction.lowLightView:
          _filters = _filters.copyWith(
            lowLightView: !_filters.lowLightView,
          );
          break;
        case _FilterAction.simulatedUv:
          _filters = _filters.copyWith(
            simulatedUv: !_filters.simulatedUv,
          );
          break;
        case _FilterAction.suspiciousDarkAreaHighlight:
          _filters = _filters.copyWith(
            suspiciousDarkAreaHighlight: !_filters.suspiciousDarkAreaHighlight,
          );
          break;
      }
    });
  }

  Future<void> _disposeController() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (error) {
      debugPrint('Erro ao parar stream da camera: $error');
    }

    await controller.dispose();
  }

  @override
  void dispose() {
    _cameraGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    _detectionService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vistoria Visual'),
        actions: [
          IconButton(
            tooltip: 'Alternar tema',
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onThemeToggle,
          ),
          if (_cameras.length > 1)
            IconButton(
              tooltip: 'Alternar camera',
              icon: const Icon(Icons.cameraswitch),
              onPressed:
                  _isInitializing ? null : () => unawaited(_cycleCamera()),
            ),
          PopupMenuButton<ResolutionPreset>(
            tooltip: 'Resolucao',
            icon: const Icon(Icons.high_quality),
            enabled: !_isInitializing,
            onSelected: (resolution) =>
                unawaited(_changeResolution(resolution)),
            itemBuilder: (context) => ResolutionPreset.values
                .map(
                  (resolution) => CheckedPopupMenuItem<ResolutionPreset>(
                    value: resolution,
                    checked: resolution == _selectedResolution,
                    child: Text(resolution.name),
                  ),
                )
                .toList(growable: false),
          ),
          PopupMenuButton<_FilterAction>(
            tooltip: 'Filtros',
            icon: const Icon(Icons.tune),
            onSelected: _toggleFilter,
            itemBuilder: (context) => [
              _filterItem(
                action: _FilterAction.simulatedThermal,
                label: 'Mapa termico simulado',
                enabled: _filters.simulatedThermal,
              ),
              _filterItem(
                action: _FilterAction.edgeHighlight,
                label: 'Realce de bordas',
                enabled: _filters.edgeHighlight,
              ),
              _filterItem(
                action: _FilterAction.contrastBoost,
                label: 'Contraste',
                enabled: _filters.contrastBoost,
              ),
              _filterItem(
                action: _FilterAction.lowLightView,
                label: 'Baixa luz simulada',
                enabled: _filters.lowLightView,
              ),
              _filterItem(
                action: _FilterAction.simulatedUv,
                label: 'UV simulado',
                enabled: _filters.simulatedUv,
              ),
              _filterItem(
                action: _FilterAction.suspiciousDarkAreaHighlight,
                label: 'Destacar areas escuras',
                enabled: _filters.suspiciousDarkAreaHighlight,
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(controller),
    );
  }

  PopupMenuEntry<_FilterAction> _filterItem({
    required _FilterAction action,
    required String label,
    required bool enabled,
  }) {
    return CheckedPopupMenuItem<_FilterAction>(
      value: action,
      checked: enabled,
      child: Text(label),
    );
  }

  Widget _buildBody(CameraController? controller) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(_setupCamera()),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isInitializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_processedImage != null)
          Image.memory(
            _processedImage!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          )
        else
          CameraPreview(controller),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _StatusBar(
            camera: _selectedCamera,
            resolution: _selectedResolution,
            aiStatus: _aiStatus,
            isRunningInference: _isRunningInference,
            tfliteResult: _tfliteResult,
          ),
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.camera,
    required this.resolution,
    required this.aiStatus,
    required this.isRunningInference,
    required this.tfliteResult,
  });

  final CameraDescription? camera;
  final ResolutionPreset resolution;
  final String aiStatus;
  final bool isRunningInference;
  final TfliteDetectionResult? tfliteResult;

  @override
  Widget build(BuildContext context) {
    final cameraLabel = switch (camera?.lensDirection) {
      CameraLensDirection.back => 'traseira',
      CameraLensDirection.front => 'frontal',
      CameraLensDirection.external => 'externa',
      null => 'camera',
    };
    final aiLabel = tfliteResult?.compactLabel ?? aiStatus;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          'RGB $cameraLabel ${resolution.name} | '
          '${isRunningInference ? 'IA analisando...' : aiLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
