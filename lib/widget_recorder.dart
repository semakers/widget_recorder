import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

Future<List<int>> optimizeImageColors(Map<String, dynamic> message) async {
  final List<int> originalBytes = message['original_bytes'];
  final int maxColors = message['max_colors'];
  final img.Image? image = img.decodeImage(Uint8List.fromList(originalBytes));
  if (image == null) {
    throw Exception('No se pudo decodificar la imagen');
  }

  final img.Image quantized = img.quantize(image, numberOfColors: maxColors);

  final List<int> optimizedBytes = img.encodePng(quantized, level: 9);

  return optimizedBytes;
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
  final WidgetRecorderController? controller;
  final void Function(WidgetRecorderResult result)? onRecordingFinished;

  const WidgetRecorder({
    super.key,
    required this.child,
    this.fps = 30,
    this.colorDepth = 32,
    this.controller,
    this.onRecordingFinished,
  });

  @override
  State<WidgetRecorder> createState() => _WidgetRecorderState();
}

class _WidgetRecorderState extends State<WidgetRecorder>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final Ticker _ticker;
  bool _isRecording = false;
  final List<List<int>> _frames = [];
  Duration _elapsed = Duration.zero;

  Future<List<int>> createWvfZip({
    required List<List<int>> frames,
    required int fps,
    required int colorDepth,
  }) async {
    final archive = Archive();

    for (int i = 0; i < frames.length; i++) {
      final fileName = 'frames/$i.png';
      final frameBytes = Uint8List.fromList(frames[i]);

      archive.addFile(ArchiveFile(fileName, frameBytes.length, frameBytes));
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
    _ticker = createTicker(_onTick);

    widget.controller?._bind(_startRecording, _stopRecording);
  }

  void _onTick(Duration elapsed) {
    final frameInterval = Duration(milliseconds: (1000 / widget.fps).round());
    if (_elapsed == Duration.zero || elapsed - _elapsed >= frameInterval) {
      _elapsed = elapsed;
      _captureFrame();
    }
  }

  Future<void> _captureFrame() async {
    if (!_isRecording) return;
    try {
      await Future.delayed(Duration.zero);

      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final optimizedBytes = await compute(optimizeImageColors, {
          'original_bytes': byteData.buffer.asUint8List(),
          'max_colors': widget.colorDepth,
        });
        _frames.add(optimizedBytes);
      }
    } catch (e) {
      debugPrint('[WidgetRecorder] Error capturando frame: $e');
    }
  }

  void _startRecording() {
    if (_isRecording) return;
    setState(() {
      _frames.clear();
      _elapsed = Duration.zero;
      _isRecording = true;
    });
    _ticker.start();
  }

  Future<List<int>> _stopRecording() async {
    if (!_isRecording) return [];
    _ticker.stop();
    setState(() => _isRecording = false);
    final fileBytes = await createWvfZip(
      frames: _frames,
      fps: widget.fps,
      colorDepth: widget.colorDepth,
    );

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
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
