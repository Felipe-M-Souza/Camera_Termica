import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:fluttertoast/fluttertoast.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detecção de Vazamentos',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: CameraScreen(
        onThemeToggle: () {
          setState(() {
            _isDarkMode = !_isDarkMode;
          });
        },
      ),
    );
  }

  final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.blue,
    ),
  );

  final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
    ),
  );
}

class CameraScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const CameraScreen({required this.onThemeToggle, super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _cameraController;
  bool _isProcessing = false;
  Uint8List? processedImage;
  bool _applyThermal = false;
  bool _applyEdges = false;
  bool _applyContrast = false;
  bool _applyNightVision = false;
  bool _applyUV = false;
  bool _applyLeakDetection = false;
  bool _alreadyShownToast = false;

  DateTime _lastProcessTime = DateTime.now();
  // late Interpreter _interpreter;
  bool _isModelLoaded = false;
  ResolutionPreset _selectedResolution =
      ResolutionPreset.low; // Resolução padrão

  @override
  void initState() {
    super.initState();
    initEverything();
  }

  void analyzeImage(img.Image image) {
    int redEdges = 0;
    int hotSpots = 0;

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        // 🔴 Rachadura: predominância de vermelho + borda
        if (r > 180 && g < 80 && b < 80) {
          redEdges++;
        }

        // 🔥 Calor simulado: vermelho ou amarelo claro
        if ((r > 200 && g > 100 && b < 100) ||
            (r > 200 && g < 100 && b < 100)) {
          hotSpots++;
        }
      }
    }

    if (!_alreadyShownToast && (redEdges > 50 || hotSpots > 50)) {
      _alreadyShownToast = true;
      Fluttertoast.showToast(
        msg: redEdges > 50
            ? "⚠️ Possível rachadura detectada!"
            : "🔥 Calor elevado detectado!",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
      );

      // Reabilita toast após 5 segundos
      Future.delayed(Duration(seconds: 5), () {
        _alreadyShownToast = false;
      });
    }
  }

  Future<void> initEverything() async {
    // await loadModel();
    await initializeCamera();
  }

  Future<void> initializeCamera() async {
    _cameraController = CameraController(
      cameras[0],
      _selectedResolution, // Definindo a resolução selecionada
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cameraController.initialize();
    _cameraController.startImageStream((CameraImage image) {
      final now = DateTime.now();
      if (!_isProcessing &&
          now.difference(_lastProcessTime).inMilliseconds > 300) {
        _lastProcessTime = now;
        _processCameraImage(image);
      }
    });
    setState(() {});
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessing = true;
    try {
      final params = _ProcessParams(
        image: image,
        applyThermal: _applyThermal,
        applyEdges: _applyEdges,
        applyContrast: _applyContrast,
        applyNightVision: _applyNightVision,
        applyUV: _applyUV,
        applyLeakDetection: _applyLeakDetection,
      );

      Uint8List result = await compute<_ProcessParams, Uint8List>(
        _processImageIsolate,
        params,
      );

      // ✅ Decodifica a imagem para análise
      final decodedImage = img.decodeImage(result);
      if (decodedImage != null) {
        analyzeImage(decodedImage); // ✅ Chamada da análise
      }

      setState(() {
        processedImage = result;
      });

      // runInference(result); // IA futura (comentado)
    } catch (e) {
      print('Erro no processamento: $e');
    } finally {
      _isProcessing = false;
    }
  }

  static Uint8List _processImageIsolate(_ProcessParams params) {
    final CameraImage image = params.image;
    img.Image rgbImage = _convertYUV420toImage(image);

    if (params.applyEdges) {
      rgbImage = img.sobel(rgbImage);
    }

    if (params.applyContrast) {
      rgbImage = img.adjustColor(rgbImage, contrast: 150);
    }

    if (params.applyThermal) {
      rgbImage = _applyThermalFilter(rgbImage);
    }

    if (params.applyNightVision) {
      rgbImage = _applyNightVisionFilter(rgbImage);
    }

    if (params.applyUV) {
      rgbImage = _applyUVFilter(rgbImage);
    }

    if (params.applyLeakDetection) {
      rgbImage = _applyLeakDetectionFilter(rgbImage);
    }

    return Uint8List.fromList(img.encodeJpg(rgbImage, quality: 50));
  }

  static img.Image _convertYUV420toImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image imgBuffer = img.Image(width: width, height: height);

    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];

    final Uint8List bytesY = planeY.bytes;
    final Uint8List bytesU = planeU.bytes;
    final Uint8List bytesV = planeV.bytes;

    final int strideY = planeY.bytesPerRow;
    final int strideU = planeU.bytesPerRow;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int indexY = y * strideY + x;
        final int uvIndex = (y ~/ 2) * strideU + (x ~/ 2);

        final int Y = bytesY[indexY];
        final int U = bytesU[uvIndex];
        final int V = bytesV[uvIndex];

        int R = (Y + (1.370705 * (V - 128))).round();
        int G = (Y - (0.337633 * (U - 128)) - (0.698001 * (V - 128))).round();
        int B = (Y + (1.732446 * (U - 128))).round();

        R = R.clamp(0, 255);
        G = G.clamp(0, 255);
        B = B.clamp(0, 255);

        imgBuffer.setPixel(x, y, img.ColorRgb8(R, G, B));
      }
    }
    return imgBuffer;
  }

  static img.Image _applyThermalFilter(img.Image src) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final r = pixel.r;
        final newColor =
            img.ColorRgb8(r.toInt(), (255 - r).toInt(), (r ~/ 2).toInt());
        src.setPixel(x, y, newColor);
      }
    }
    return src;
  }

  static img.Image _applyNightVisionFilter(img.Image src) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final avg = ((pixel.r + pixel.g + pixel.b) ~/ 3).clamp(0, 255);
        final nightColor = img.ColorRgb8(0, avg, 0); // Verde
        src.setPixel(x, y, nightColor);
      }
    }
    return src;
  }

  static img.Image _applyUVFilter(img.Image src) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final r = (pixel.r * 1.2).clamp(0, 255).toInt();
        final g = (pixel.g * 0.6).clamp(0, 255).toInt();
        final b = (pixel.b * 1.5).clamp(0, 255).toInt();
        final uvColor = img.ColorRgb8(r, g, b);
        src.setPixel(x, y, uvColor);
      }
    }
    return src;
  }

  static img.Image _applyLeakDetectionFilter(img.Image src) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final brightness =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
        if (brightness < 50) {
          // Áreas muito escuras
          src.setPixel(x, y, img.ColorRgb8(255, 0, 0)); // Vermelho
        }
      }
    }
    return src;
  }

  Future<void> runInference(Uint8List imageBytes) async {
    if (!_isModelLoaded) {
      print('Erro: Modelo não carregado ainda.');
      return;
    }

    var output = List.filled(1, 0);
    // _interpreter.run(imageBytes, output);
    print("Análise de IA: $output");
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detecção de Vazamentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onThemeToggle,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'thermal':
                    _applyThermal = !_applyThermal;
                    break;
                  case 'edges':
                    _applyEdges = !_applyEdges;
                    break;
                  case 'contrast':
                    _applyContrast = !_applyContrast;
                    break;
                  case 'nightVision':
                    _applyNightVision = !_applyNightVision;
                    break;
                  case 'uv':
                    _applyUV = !_applyUV;
                    break;
                  case 'leak':
                    _applyLeakDetection = !_applyLeakDetection;
                    break;
                }
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'thermal',
                child: Text(
                    _applyThermal ? 'Desativar Térmico' : 'Ativar Térmico'),
              ),
              PopupMenuItem<String>(
                value: 'edges',
                child: Text(_applyEdges ? 'Desativar Bordas' : 'Ativar Bordas'),
              ),
              PopupMenuItem<String>(
                value: 'contrast',
                child: Text(_applyContrast
                    ? 'Desativar Contraste'
                    : 'Ativar Contraste'),
              ),
              PopupMenuItem<String>(
                value: 'nightVision',
                child: Text(_applyNightVision
                    ? 'Desativar Visão Noturna'
                    : 'Ativar Visão Noturna'),
              ),
              PopupMenuItem<String>(
                value: 'uv',
                child: Text(_applyUV ? 'Desativar UV' : 'Ativar UV'),
              ),
              PopupMenuItem<String>(
                value: 'leak',
                child: Text(_applyLeakDetection
                    ? 'Desativar Detecção Vazamento'
                    : 'Ativar Detecção Vazamento'),
              ),
            ],
          ),
          DropdownButton<ResolutionPreset>(
            value: _selectedResolution,
            items: ResolutionPreset.values
                .map((resolution) => DropdownMenuItem<ResolutionPreset>(
                      value: resolution,
                      child: Text(resolution.toString().split('.').last),
                    ))
                .toList(),
            onChanged: (ResolutionPreset? newValue) {
              setState(() {
                _selectedResolution = newValue!;
                // Reinicia a câmera com a nova resolução
                initializeCamera();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: processedImage != null
                ? Image.memory(
                    processedImage!,
                    fit: BoxFit.cover,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

class _ProcessParams {
  final CameraImage image;
  final bool applyThermal;
  final bool applyEdges;
  final bool applyContrast;
  final bool applyNightVision;
  final bool applyUV;
  final bool applyLeakDetection;

  _ProcessParams({
    required this.image,
    required this.applyThermal,
    required this.applyEdges,
    required this.applyContrast,
    required this.applyNightVision,
    required this.applyUV,
    required this.applyLeakDetection,
  });
}
