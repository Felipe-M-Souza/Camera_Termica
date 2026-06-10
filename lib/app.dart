import 'package:flutter/material.dart';
import 'package:vazamento_detector/features/camera/camera_screen.dart';

class VazamentoDetectorApp extends StatefulWidget {
  const VazamentoDetectorApp({super.key});

  @override
  State<VazamentoDetectorApp> createState() => _VazamentoDetectorAppState();
}

class _VazamentoDetectorAppState extends State<VazamentoDetectorApp> {
  var _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vistoria Visual',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
}
