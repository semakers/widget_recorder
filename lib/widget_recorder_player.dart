// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

// Parámetros para procesamiento de frames en isolate
class FrameProcessingParams {
  final List<int> zipBytes;
  final String tempDirectoryPath;
  final Size? targetSize;

  FrameProcessingParams({
    required this.zipBytes,
    required this.tempDirectoryPath,
    this.targetSize,
  });
}

// Resultado del procesamiento de frames
class FrameProcessingResult {
  final int fps;
  final int frameCount;
  final List<String> framePaths;

  FrameProcessingResult({
    required this.fps,
    required this.frameCount,
    required this.framePaths,
  });
}

// Función para procesar el ZIP y redimensionar frames en isolate
Future<FrameProcessingResult?> _processWvfInIsolate(
  FrameProcessingParams params,
) async {
  try {
    // Crear directorio temporal
    final sessionDir = Directory(params.tempDirectoryPath);
    await sessionDir.create(recursive: true);

    // Descomprimir ZIP
    final archive = ZipDecoder().decodeBytes(params.zipBytes);

    // Leer metadatos
    final metaFile = archive.firstWhere((f) => f.name == 'meta.json');
    final metaJson =
        jsonDecode(utf8.decode(metaFile.content)) as Map<String, dynamic>;
    final fps = metaJson['fps'] as int;
    final frameCount = metaJson['frameCount'] as int;

    final framePaths = <String>[];

    // Procesar cada frame
    for (int i = 0; i < frameCount; i++) {
      final frameFile = archive.firstWhere((f) => f.name == 'frames/$i.png');
      final frameBytes = Uint8List.fromList(frameFile.content as List<int>);

      Uint8List finalBytes = frameBytes;

      // Redimensionar si se especifica un tamaño
      if (params.targetSize != null) {
        final originalImage = img.decodeImage(frameBytes);
        if (originalImage != null) {
          final originalAspectRatio =
              originalImage.width / originalImage.height;
          final targetAspectRatio =
              params.targetSize!.width / params.targetSize!.height;

          int newWidth, newHeight;
          if (originalAspectRatio > targetAspectRatio) {
            newWidth = params.targetSize!.width.round();
            newHeight = (newWidth / originalAspectRatio).round();
          } else {
            newHeight = params.targetSize!.height.round();
            newWidth = (newHeight * originalAspectRatio).round();
          }

          final resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
            interpolation: img.Interpolation.linear,
          );

          finalBytes = Uint8List.fromList(img.encodePng(resizedImage));
        }
      }

      // Guardar frame procesado
      final framePath = path.join(params.tempDirectoryPath, '$i.png');
      final file = File(framePath);
      await file.writeAsBytes(finalBytes);
      framePaths.add(framePath);
    }

    return FrameProcessingResult(
      fps: fps,
      frameCount: frameCount,
      framePaths: framePaths,
    );
  } catch (e) {
    print('Error processing FWA in isolate: $e');
    return null;
  }
}

// Sistema de caché de frames compartido
class FrameCache {
  static final FrameCache _instance = FrameCache._internal();
  factory FrameCache() => _instance;
  FrameCache._internal();

  final Map<String, ui.Image> _cache = {};
  final Map<String, Future<ui.Image?>> _loadingCache = {};

  // Obtener frame del caché o cargarlo
  Future<ui.Image?> getFrame(String framePath) async {
    // Si ya está en caché, devolverlo
    if (_cache.containsKey(framePath)) {
      return _cache[framePath];
    }

    // Si ya se está cargando, esperar el resultado
    if (_loadingCache.containsKey(framePath)) {
      return await _loadingCache[framePath];
    }

    // Iniciar carga
    final loadingFuture = _loadFrameFromDisk(framePath);
    _loadingCache[framePath] = loadingFuture;

    final image = await loadingFuture;
    _loadingCache.remove(framePath);

    if (image != null) {
      _cache[framePath] = image;
    }

    return image;
  }

  Future<ui.Image?> _loadFrameFromDisk(String framePath) async {
    try {
      final file = File(framePath);
      if (!await file.exists()) {
        return null;
      }

      final frameBytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(frameBytes);
      final fi = await codec.getNextFrame();
      return fi.image;
    } catch (e) {
      print('Error loading frame from cache: $e');
      return null;
    }
  }

  // Limpiar frames específicos del caché
  void clearFrames(List<String> framePaths) {
    for (final framePath in framePaths) {
      final image = _cache.remove(framePath);
      image?.dispose();
    }
  }

  // Limpiar todo el caché
  void clearAll() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _loadingCache.clear();
  }
}

class WidgetRecorderPlayer extends StatefulWidget {
  final List<int> fwaBytes;
  final Size? size;

  const WidgetRecorderPlayer({super.key, required this.fwaBytes, this.size});

  @override
  State<WidgetRecorderPlayer> createState() => _WidgetRecorderPlayerState();
}

class _WidgetRecorderPlayerState extends State<WidgetRecorderPlayer>
    with SingleTickerProviderStateMixin {
  late int fps;
  late int frameCount;
  String? _tempDirectoryPath;
  List<String> _framePaths = [];
  AnimationController? _controller;
  ui.Image? _currentFrame;
  int _currentFrameIndex = -1;
  bool _isInitialized = false;
  final _frameCache = FrameCache();

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // Generar directorio temporal único
      final tempDir = await getTemporaryDirectory();
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _tempDirectoryPath = path.join(
        tempDir.path,
        'widget_recorder_$sessionId',
      );

      // Procesar FWA en isolate
      final result = await compute(
        _processWvfInIsolate,
        FrameProcessingParams(
          zipBytes: widget.fwaBytes,
          tempDirectoryPath: _tempDirectoryPath!,
          targetSize: widget.size,
        ),
      );

      if (result != null && mounted) {
        fps = result.fps;
        frameCount = result.frameCount;
        _framePaths = result.framePaths;

        // Crear controlador de animación
        _controller = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (frameCount / fps * 1000).toInt()),
        )..repeat();

        _isInitialized = true;
        setState(() {});
      }
    } catch (e) {
      print('Error initializing player: $e');
    }
  }

  Future<void> _updateCurrentFrame(int frameIndex) async {
    if (_currentFrameIndex == frameIndex ||
        frameIndex < 0 ||
        frameIndex >= _framePaths.length) {
      return;
    }

    try {
      final framePath = _framePaths[frameIndex];
      final newFrame = await _frameCache.getFrame(framePath);

      if (newFrame != null && mounted) {
        _currentFrame = newFrame;
        _currentFrameIndex = frameIndex;

        // No dispose del frame anterior porque puede estar en caché compartido
        // El caché se encarga de la gestión de memoria

        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      print('Error updating frame $frameIndex: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      if (widget.size != null) {
        return SizedBox(
          width: widget.size!.width,
          height: widget.size!.height,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        final frameIndex =
            (_controller!.value * frameCount).floor() % frameCount;

        _updateCurrentFrame(frameIndex);

        if (_currentFrame == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Si se especifica un tamaño, usar ese tamaño específico
        if (widget.size != null) {
          return SizedBox(
            width: widget.size!.width,
            height: widget.size!.height,
            child: CustomPaint(
              painter: _FramePainter(_currentFrame!),
              size: widget.size!,
            ),
          );
        }

        // Si no se especifica tamaño, usar Row + Expanded + LayoutBuilder
        return Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (_currentFrame != null) {
                    final imageAspectRatio =
                        _currentFrame!.width / _currentFrame!.height;
                    final calculatedHeight =
                        constraints.maxWidth / imageAspectRatio;

                    return SizedBox(
                      width: constraints.maxWidth,
                      height: calculatedHeight,
                      child: CustomPaint(
                        painter: _FramePainter(_currentFrame!),
                        size: Size(constraints.maxWidth, calculatedHeight),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    if (_tempDirectoryPath != null) {
      try {
        // Limpiar frames del caché
        _frameCache.clearFrames(_framePaths);

        // Eliminar directorio temporal
        final sessionDir = Directory(_tempDirectoryPath!);
        if (await sessionDir.exists()) {
          await sessionDir.delete(recursive: true);
        }
      } catch (e) {
        print('Error cleaning up temp files: $e');
      }
    }
  }
}

class _FramePainter extends CustomPainter {
  final ui.Image frame;

  _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    if (size.isInfinite) {
      canvas.drawImage(frame, Offset.zero, paint);
    } else {
      if (frame.width.toDouble() == size.width &&
          frame.height.toDouble() == size.height) {
        canvas.drawImage(frame, Offset.zero, paint);
      } else {
        final double scaleX = size.width / frame.width;
        final double scaleY = size.height / frame.height;

        final double scale = scaleX < scaleY ? scaleX : scaleY;

        final double scaledWidth = frame.width * scale;
        final double scaledHeight = frame.height * scale;
        final double offsetX = (size.width - scaledWidth) / 2;
        final double offsetY = (size.height - scaledHeight) / 2;

        canvas.save();
        canvas.translate(offsetX, offsetY);
        canvas.scale(scale);
        canvas.drawImage(frame, Offset.zero, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) =>
      oldDelegate.frame != frame;
}
