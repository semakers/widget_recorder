

# 🎬 widget_recorder: Flutter Widget Animation (.fwa)

## What is `.fwa` and Why Does It Exist?

**widget_recorder** brings the `.fwa` (Flutter Widget Animation) format: a new, efficient way to record and play back widget animations in Flutter apps. `.fwa` is not a video or audio file—it's a ZIP containing PNG frames and a `meta.json` (fps, colorDepth, frameCount, etc.), designed for maximum efficiency and control in Flutter UIs.

## Why Not Just Use GIF?

- **GIFs** are heavy, lossy, and lack playback control (no pause, no seek, no loop customization).
- **.fwa** is optimized for Flutter: smaller file size, better performance, and full playback control (play, pause, loop, seek, etc.).

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
	widget_recorder: ^<latest_version>
```

Then run:

```sh
flutter pub get
```

---

## Usage

### 1. Recording an Animation

```dart
import 'package:widget_recorder/widget_recorder.dart';

final WidgetRecorderController _controller = WidgetRecorderController();

WidgetRecorder(
	controller: _controller,
	fps: 15, // Optional: frames per second
	colorDepth: 16, // Optional: color quantization
	onRecordingFinished: (result) async {
		// result.fileBytes contains the .fwa file (ZIP with PNGs + meta.json)
		// You can save it or use it directly with WidgetRecorderPlayer
	},
	child: Stack(
		children: [
			ProgrammingPage(), // Your animated widget
			Positioned(
				top: 20,
				right: 20,
				child: Column(
					children: [
						ElevatedButton(
							onPressed: _controller.start,
							child: const Text('Start recording'),
						),
						ElevatedButton(
							onPressed: _controller.stop,
							child: const Text('Stop recording'),
						),
					],
				),
			),
		],
	),
);
```

### 2. Playing Back an Animation

```dart
import 'package:widget_recorder/widget_recorder_player.dart';

WidgetRecorderPlayer(
	fwaBytes: result.fileBytes, // The .fwa bytes from recording
	size: Size(100, 100),      // Optional: display size
)
```

---

## Features

- ⚡ **Lightweight**: Only PNG frames + minimal JSON metadata, zipped
- 🚀 **Fast**: No video decoding, instant frame rendering
- 🧩 **Compatible**: Works on all Flutter platforms (mobile, web, desktop)
- 🎯 **Purpose-built**: Designed for widget tutorials, feature demos, onboarding, and more

---

> ".fwa is to Flutter what .gif was to the web: a lightweight, simple way to share widget animations."

---

**Made with ❤️ for the Flutter community.**
