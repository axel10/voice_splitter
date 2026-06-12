// ignore_for_file: avoid_print
// Copyright (c) 2026 Antigravity
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:voice_splitter/voice_splitter.dart';
import 'package:voice_splitter/src/wav_helper.dart';

void main() async {
  print('=== Voice Splitter Local Verification Script ===\n');

  final currentDir = Directory.current.path;
  final tempDir = Directory(path.join(currentDir, 'test_temp'));
  if (!tempDir.existsSync()) {
    tempDir.createSync();
  }

  final testInputPath = path.join(tempDir.path, 'test_input.wav');
  final modelPath = path.join(tempDir.path, 'UVR_MDXNET_9482.onnx');

  // 1. Auto-detect library path on desktop platforms
  String? libraryPath;
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      final configPath = path.join(currentDir, '.dart_tool', 'package_config.json');
      final configFile = File(configPath);
      if (configFile.existsSync()) {
        final config = jsonDecode(configFile.readAsStringSync());
        final packages = config['packages'] as List;
        
        String pkgName = '';
        String subDir = '';
        if (Platform.isMacOS) {
          pkgName = 'sherpa_onnx_macos';
          subDir = 'macos';
        } else if (Platform.isWindows) {
          pkgName = 'sherpa_onnx_windows';
          subDir = 'windows';
        } else if (Platform.isLinux) {
          pkgName = 'sherpa_onnx_linux';
          subDir = 'linux';
        }

        final pkg = packages.firstWhere((p) => p['name'] == pkgName, orElse: () => null);
        if (pkg != null) {
          final rootUri = Uri.parse(pkg['rootUri'] as String);
          libraryPath = path.join(rootUri.toFilePath(), subDir);
          print('Auto-detected native library path: $libraryPath');
        }
      }
    } catch (e) {
      print('Note: Failed to auto-detect library path (will fall back to default dynamic linking): $e');
    }
  }

  // 2. Synthesize a 3-second stereo WAV file if it doesn't exist
  print('Generating synthetic stereo WAV file...');
  _generateStereoSineWave(testInputPath, 3.0, 44100);
  print('Saved synthetic WAV to: $testInputPath');

  // 3. Download the model if it doesn't exist
  if (!File(modelPath).existsSync()) {
    print('Model UVR_MDXNET_9482.onnx not found locally.');
    final modelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/UVR_MDXNET_9482.onnx';
    print('Downloading model from: $modelUrl');
    await _downloadFile(modelUrl, modelPath);
  } else {
    print('Model found locally at: $modelPath');
  }

  // 4. Run separation
  print('\nRunning voice split (vocal separation) in background isolate...');
  final stopwatch = Stopwatch()..start();
  
  try {
    final result = await VoiceSplitter.split(
      audioPath: testInputPath,
      modelPath: modelPath,
      numThreads: 4,
      debug: true,
      libraryPath: libraryPath,
    );

    stopwatch.stop();
    print('\n======================================');
    print('SUCCESS: Voice Split Completed!');
    print('Time elapsed: ${stopwatch.elapsed.inMilliseconds / 1000}s');
    print('Vocals path: ${result.vocalsPath}');
    print('Accompaniment path: ${result.accompanimentPath}');
    print('Sample rate: ${result.sampleRate} Hz');
    print('Total samples: ${result.numSamples}');
    print('======================================');

    // Simple validation checks
    final vocalsFile = File(result.vocalsPath);
    final bgmFile = File(result.accompanimentPath);
    if (vocalsFile.existsSync() && bgmFile.existsSync()) {
      print('Output files verified on disk (Vocals: ${vocalsFile.lengthSync()} bytes, BGM: ${bgmFile.lengthSync()} bytes)');
    } else {
      print('Warning: Output files are missing!');
    }
  } catch (e, stackTrace) {
    stopwatch.stop();
    print('\nERROR: Vocal separation failed!');
    print(e);
    print(stackTrace);
  }
}

/// Generates a stereo sine wave (440Hz Left, 880Hz Right) and writes it as a 16-bit PCM WAV.
void _generateStereoSineWave(String filePath, double duration, int sampleRate) {
  final numFrames = (duration * sampleRate).toInt();
  final left = Float32List(numFrames);
  final right = Float32List(numFrames);

  const freqLeft = 440.0;
  const freqRight = 880.0;

  for (int i = 0; i < numFrames; i++) {
    final t = i / sampleRate;
    left[i] = sin(2.0 * pi * freqLeft * t) * 0.5;   // Scale amplitude to 0.5
    right[i] = sin(2.0 * pi * freqRight * t) * 0.5; // Scale amplitude to 0.5
  }

  WavHelper.write(
    filePath,
    WavData(channels: [left, right], sampleRate: sampleRate),
  );
}

/// Helper to download file with basic console progress reporting.
Future<void> _downloadFile(String url, String savePath) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    
    if (response.statusCode != 200) {
      throw HttpException('Failed to download file: status code ${response.statusCode}');
    }

    final file = File(savePath);
    final sink = file.openWrite();
    
    final totalLength = response.contentLength;
    int received = 0;
    
    print('Downloading... 0%');

    await response.forEach((chunk) {
      sink.add(chunk);
      received += chunk.length;
      if (totalLength > 0) {
        final percentage = (received / totalLength * 100).toStringAsFixed(1);
        stdout.write('\rDownloading... $percentage% (${(received / (1024 * 1024)).toStringAsFixed(1)}MB / ${(totalLength / (1024 * 1024)).toStringAsFixed(1)}MB)');
      }
    });

    await sink.flush();
    await sink.close();
    print('\nDownload completed and saved to: $savePath');
  } catch (e) {
    print('\nDownload failed: $e');
    rethrow;
  } finally {
    client.close();
  }
}
