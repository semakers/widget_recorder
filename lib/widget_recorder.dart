import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Nueva función para procesar captura completa en isolate
Future<List<int>?> processFrameCapture(
    List<int> imageBytes, int colorDepth) async {
  try {
    // Solo optimizar si es necesario
    if (colorDepth < 256) {
      final img.Image? image = img.decodeImage(Uint8List.fromList(imageBytes));
      if (image == null) return imageBytes;

      final img.Image quantized = img.quantize(
        image,
        numberOfColors: colorDepth,
      );
      return img.encodePng(quantized, level: 6);
    } else {
      return imageBytes;
    }
  } catch (e) {
    debugPrint('[WidgetRecorder] Error procesando frame: $e');
    return imageBytes; // Retornar original en caso de error
  }
}

class WidgetRecorderController {
  VoidCallback? _startCallback;
  Future<List<int>> Function()? _stopCallback;

  void _bind(VoidCallback start, Future<List<int>> Function() stop) {
    _startCallback = start;
    _stopCallback = stop;
  }

  void start() => _startCallback?.call();

  Future<List<int>> stop() async {
    final bytes = await _stopCallback?.call();
    return bytes ?? [];
  }
}

class WidgetRecorderResult {
  final List<int> fileBytes;
  final int fps;
  final int colorDepth;

  WidgetRecorderResult({
    required this.fileBytes,
    required this.fps,
    required this.colorDepth,
  });
}

class WidgetRecorder extends StatefulWidget {
  final Widget child;
  final int fps;
  final int colorDepth;
  final int maxFrames; // Nuevo parámetro para limitar frames en memoria
  final WidgetRecorderController? controller;
  final void Function(WidgetRecorderResult result)? onRecordingFinished;

  const WidgetRecorder({
    Key? key,
    required this.child,
    this.fps = 30,
    this.colorDepth = 32,
    this.maxFrames = 1800, // 60 segundos a 30fps por defecto
    this.controller,
    this.onRecordingFinished,
  }) : super(key: key);

  @override
  State<WidgetRecorder> createState() => _WidgetRecorderState();
}

class _WidgetRecorderState extends State<WidgetRecorder>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  Timer? _captureTimer;
  bool _isRecording = false;
  bool _isCapturing = false; // Bloqueo simple pero efectivo
  final List<List<int>> _frames = [];

  Future<List<int>> createWvfZip({
    required List<List<int>> frames,
    required int fps,
    required int colorDepth,
  }) async {
    final archive = Archive();

    for (int i = 0; i < frames.length; i++) {
      final fileName = 'frames/$i.png';
      final frameBytes = await processFrameCapture(frames[i], colorDepth);

      archive.addFile(ArchiveFile(fileName, frameBytes!.length, frameBytes));
    }

    final meta = {
      'fps': fps,
      'colorDepth': colorDepth,
      'frameCount': frames.length,
      'version': '1.0.0',
    };

    final metaBytes = utf8.encode(jsonEncode(meta));
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

    final zipData = ZipEncoder().encode(archive);
    final bytes = Uint8List.fromList(zipData);

    return bytes;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(_startRecording, _stopRecording);
  }

  void _startTimer() {
    final intervalMs = (1000 / widget.fps).round();
    _captureTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      // SIMPLE: Si está ocupado, saltar este frame (mantener UI fluida)
      if (!_isCapturing) {
        _captureFrame();
      }
    });
  }

  Future<void> _captureFrame() async {
    if (!_isRecording) return;

    _isCapturing = true;

    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _isCapturing = false;
        return;
      }

      // Capturar imagen y forzar formato de 8 bits por canal
      final image = await boundary.toImage();

      // Forzar formato de 8 bits por canal usando rawRgba
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null && _isRecording) {
        // Convertir RGBA raw a PNG de 8 bits
        final width = image.width;
        final height = image.height;
        final rgba = byteData.buffer.asUint8List();

        // Crear imagen con el paquete image (forzará 8 bits)
        final img.Image imgImage = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgba.buffer,
          format: img.Format.uint8,
          numChannels: 4,
        );

        // Codificar a PNG de 8 bits
        final imageBytes = img.encodePng(imgImage);

        if (_frames.length >= widget.maxFrames) {
          _frames.removeAt(0);
        }
        _frames.add(imageBytes);
      }
    } catch (e) {
      debugPrint('[WidgetRecorder] Error capturando frame: $e');
    } finally {
      _isCapturing = false;
    }
  }

  void _startRecording() {
    if (_isRecording) return;
    setState(() {
      _frames.clear();
      _isRecording = true;
    });
    _startTimer();
  }

  Future<List<int>> _stopRecording() async {
    if (!_isRecording) return [];

    _captureTimer?.cancel();
    setState(() => _isRecording = false);

    // Crear una copia de los frames antes de limpiar
    final framesCopy = List<List<int>>.from(_frames);

    final fileBytes = await createWvfZip(
      frames: framesCopy,
      fps: widget.fps,
      colorDepth: widget.colorDepth,
    );

    // Limpiar la memoria
    _frames.clear();

    widget.onRecordingFinished?.call(
      WidgetRecorderResult(
        fileBytes: fileBytes,
        fps: widget.fps,
        colorDepth: widget.colorDepth,
      ),
    );
    return fileBytes;
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
