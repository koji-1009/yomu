import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yomu/yomu.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ScannerScreen());
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  DecoderResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status != .granted) {
      setState(() {
        _error = 'Camera permission denied';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No cameras found';
        });
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == .back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(camera, .medium, enableAudio: false);
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() {});

      await controller.startImageStream(_processImage);
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Run decoding in a separate isolate to avoid blocking the UI thread
      final result = await compute(_decode, image);

      if (mounted && result != null) {
        setState(() {
          _result = result;
        });
      }
    } catch (e) {
      // Ignore decoding errors (no QR code found)
    } finally {
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('QR Scanner')),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_result != null)
            Align(
              alignment: .bottomCenter,
              child: Padding(
                padding: const .all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: .all(.circular(8)),
                  ),
                  child: Padding(
                    padding: const .all(16),
                    child: Text(
                      _result!.text,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Top-level function for isolate
DecoderResult? _decode(CameraImage image) {
  try {
    final width = image.width;
    final height = image.height;
    final yomuImage = switch (image.format.group) {
      .yuv420 || .nv21 => YomuImage.yuv420(
        yBytes: image.planes[0].bytes,
        width: width,
        height: height,
        yRowStride: image.planes[0].bytesPerRow,
      ),
      .bgra8888 => YomuImage.bgra(
        bytes: image.planes[0].bytes,
        width: width,
        height: height,
        rowStride: image.planes[0].bytesPerRow,
      ),
      _ => null,
    };

    if (yomuImage == null) {
      return null;
    }

    final result = Yomu.all.decode(yomuImage);
    return result;
  } catch (e) {
    return null;
  }
}
