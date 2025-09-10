import 'package:flutter/material.dart';
import 'package:programming_blocks/programming_blocks.dart';
import 'package:flutter_widget_recorder/widget_recorder.dart';
import 'package:flutter_widget_recorder/widget_recorder_player.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ManualRecordingWrapper();
  }
}

class ProgrammingPage extends StatelessWidget {
  const ProgrammingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: WidgetRecorder(
          child: ProgrammingBlocks(
            sections: [FollowSection(), LogicSection(), NumbersSection()],
          ),
        ),
      ),
    );
  }
}

class ManualRecordingWrapper extends StatefulWidget {
  const ManualRecordingWrapper({super.key});

  @override
  State<ManualRecordingWrapper> createState() => _ManualRecordingWrapperState();
}

class _ManualRecordingWrapperState extends State<ManualRecordingWrapper> {
  final WidgetRecorderController _controller = WidgetRecorderController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return WidgetRecorder(
            controller: _controller,
            fps: 15,
            colorDepth: 16,
            onRecordingFinished: (result) async {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ListView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: 50,
                    itemBuilder: (_, __) {
                      return WidgetRecorderPlayer(
                        fwaBytes: result.fileBytes,
                        size: Size(100, 100),
                      );
                    },
                  ),
                ),
              );
              /* final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/recording.fwa');
              await file.writeAsBytes(result.fileBytes);*/

              // TODO: Guardar .fwa, mostrar preview, etc.
            },
            child: MaterialApp(
              home: Stack(
                children: [
                  ProgrammingPage(),
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: _controller.start,
                          child: const Text('Iniciar grabación'),
                        ),
                        ElevatedButton(
                          onPressed: _controller.stop,
                          child: const Text('Detener grabación'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
