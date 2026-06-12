// Copyright (c) 2026 Antigravity
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as path;
import 'package:voice_splitter/voice_splitter.dart';

void main() {
  runApp(const VoiceSplitterExampleApp());
}

class VoiceSplitterExampleApp extends StatelessWidget {
  const VoiceSplitterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Splitter AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F111A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFFEC4899),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E2132),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Paths
  String? _modelPath;
  String? _inputAudioPath;
  String? _vocalsAudioPath;
  String? _accompanimentAudioPath;

  // Statuses
  bool _isDownloadingModel = false;
  double _downloadProgress = 0.0;
  bool _isProcessing = false;
  String _statusMessage = 'Ready';
  bool _useHardwareAccel = true;
  
  // Audio Players
  final AudioPlayer _originalPlayer = AudioPlayer();
  final AudioPlayer _vocalsPlayer = AudioPlayer();
  final AudioPlayer _accompanimentPlayer = AudioPlayer();

  // Playback States
  PlayerState _originalState = PlayerState.stopped;
  PlayerState _vocalsState = PlayerState.stopped;
  PlayerState _accompanimentState = PlayerState.stopped;

  Duration _originalDuration = Duration.zero;
  Duration _vocalsDuration = Duration.zero;
  Duration _accompanimentDuration = Duration.zero;

  Duration _originalPosition = Duration.zero;
  Duration _vocalsPosition = Duration.zero;
  Duration _accompanimentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _checkLocalModel();
    _setupAudioListeners();
  }

  @override
  void dispose() {
    _originalPlayer.dispose();
    _vocalsPlayer.dispose();
    _accompanimentPlayer.dispose();
    super.dispose();
  }

  // Check if model already exists locally
  Future<void> _checkLocalModel() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelFile = File(path.join(appDir.path, 'UVR_MDXNET_9482.onnx'));
    if (modelFile.existsSync()) {
      setState(() {
        _modelPath = modelFile.path;
      });
    }
  }

  // Setup Audio Player Event Listeners
  void _setupAudioListeners() {
    // Original Player
    _originalPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _originalState = state);
    });
    _originalPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _originalDuration = d);
    });
    _originalPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _originalPosition = p);
    });

    // Vocals Player
    _vocalsPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _vocalsState = state);
    });
    _vocalsPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _vocalsDuration = d);
    });
    _vocalsPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _vocalsPosition = p);
    });

    // Accompaniment Player
    _accompanimentPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _accompanimentState = state);
    });
    _accompanimentPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _accompanimentDuration = d);
    });
    _accompanimentPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _accompanimentPosition = p);
    });
  }

  // Download the lightweight UVR MDX-Net ONNX model
  Future<void> _downloadModel() async {
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Downloading AI model...';
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final savePath = path.join(appDir.path, 'UVR_MDXNET_9482.onnx');
      final url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/UVR_MDXNET_9482.onnx';

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('Server returned code ${response.statusCode}');
      }

      final file = File(savePath);
      final sink = file.openWrite();
      final total = response.contentLength;
      int received = 0;

      await response.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          setState(() {
            _downloadProgress = received / total;
          });
        }
      });

      await sink.flush();
      await sink.close();
      client.close();

      setState(() {
        _modelPath = savePath;
        _isDownloadingModel = false;
        _statusMessage = 'Model ready';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI Model downloaded successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloadingModel = false;
        _statusMessage = 'Model download failed';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download model: $e')),
        );
      }
    }
  }

  // Pick a local WAV file
  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );

      if (result != null && result.files.single.path != null) {
        // Stop any current playback
        await _stopAllPlayers();
        
        setState(() {
          _inputAudioPath = result.files.single.path;
          _vocalsAudioPath = null;
          _accompanimentAudioPath = null;
          _statusMessage = 'WAV Audio loaded';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  // Synthesize a stereo sine wave (Left 440Hz, Right 880Hz) to test instantly
  Future<void> _generateTestAudio() async {
    await _stopAllPlayers();
    setState(() {
      _statusMessage = 'Synthesizing test audio...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final testPath = path.join(tempDir.path, 'voice_splitter_test_input.wav');
      
      final sampleRate = 44100;
      final duration = 3.0; // 3 seconds
      final numFrames = (duration * sampleRate).toInt();
      
      final left = Float32List(numFrames);
      final right = Float32List(numFrames);

      for (int i = 0; i < numFrames; i++) {
        final t = i / sampleRate;
        left[i] = sin(2.0 * pi * 440.0 * t) * 0.5; // Sine wave Left
        right[i] = sin(2.0 * pi * 880.0 * t) * 0.5; // Sine wave Right
      }

      // Write WAV file bytes
      final dataSize = numFrames * 2 * 2;
      final bytes = Uint8List(44 + dataSize);
      final byteData = ByteData.sublistView(bytes);

      // RIFF header
      byteData.setUint8(0, 0x52); // R
      byteData.setUint8(1, 0x49); // I
      byteData.setUint8(2, 0x46); // F
      byteData.setUint8(3, 0x46); // F
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      byteData.setUint8(8, 0x57); // W
      byteData.setUint8(9, 0x41); // A
      byteData.setUint8(10, 0x56); // V
      byteData.setUint8(11, 0x45); // E

      // fmt Subchunk
      byteData.setUint8(12, 0x66); // f
      byteData.setUint8(13, 0x6d); // m
      byteData.setUint8(14, 0x74); // t
      byteData.setUint8(15, 0x20); //  
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little); // PCM format
      byteData.setUint16(22, 2, Endian.little); // 2 channels
      byteData.setUint32(24, sampleRate, Endian.little);
      byteData.setUint32(28, sampleRate * 2 * 2, Endian.little); // byte rate
      byteData.setUint16(32, 4, Endian.little); // block align
      byteData.setUint16(34, 16, Endian.little); // bits per sample

      // data Subchunk
      byteData.setUint8(36, 0x64); // d
      byteData.setUint8(37, 0x61); // a
      byteData.setUint8(38, 0x74); // t
      byteData.setUint8(39, 0x61); // a
      byteData.setUint32(40, dataSize, Endian.little);

      int offset = 44;
      for (int i = 0; i < numFrames; i++) {
        final clampedL = left[i].clamp(-1.0, 1.0);
        final clampedR = right[i].clamp(-1.0, 1.0);
        byteData.setInt16(offset, (clampedL * 32767.0).round(), Endian.little);
        byteData.setInt16(offset + 2, (clampedR * 32767.0).round(), Endian.little);
        offset += 4;
      }

      await File(testPath).writeAsBytes(bytes);

      setState(() {
        _inputAudioPath = testPath;
        _vocalsAudioPath = null;
        _accompanimentAudioPath = null;
        _statusMessage = 'Test audio synthesized';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synthetic stereo WAV generated!')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Synthesis failed';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to synthesize audio: $e')),
        );
      }
    }
  }

  // Trigger vocal separation
  Future<void> _processSeparation() async {
    if (_inputAudioPath == null || _modelPath == null) return;
    
    await _stopAllPlayers();

    setState(() {
      _isProcessing = true;
      _statusMessage = 'AI separating vocals from accompaniment...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final tempDir = await getTemporaryDirectory();
      final baseName = path.basenameWithoutExtension(_inputAudioPath!);
      final vocalsOut = path.join(tempDir.path, '${baseName}_vocals.wav');
      final accompanimentOut = path.join(tempDir.path, '${baseName}_accompaniment.wav');

      String provider = 'cpu';
      if (_useHardwareAccel) {
        if (Platform.isMacOS || Platform.isIOS) {
          provider = 'coreml';
        } else if (Platform.isAndroid) {
          provider = 'nnapi';
        } else if (Platform.isWindows) {
          provider = 'directml';
        }
      }

      final result = await VoiceSplitter.split(
        audioPath: _inputAudioPath!,
        modelPath: _modelPath!,
        outVocalsPath: vocalsOut,
        outAccompanimentPath: accompanimentOut,
        numThreads: 4,
        provider: provider,
        debug: true,
      );

      stopwatch.stop();

      setState(() {
        _vocalsAudioPath = result.vocalsPath;
        _accompanimentAudioPath = result.accompanimentPath;
        _isProcessing = false;
        _statusMessage = 'Separation complete in ${(_originalDuration.inMilliseconds == 0 ? stopwatch.elapsed.inMilliseconds / 1000 : stopwatch.elapsed.inSeconds).toStringAsFixed(1)}s!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vocal separation complete in ${stopwatch.elapsed.inSeconds}s!')),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Separation failed';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Separation failed: $e')),
        );
      }
    }
  }

  // Helper to stop all audio players
  Future<void> _stopAllPlayers() async {
    await _originalPlayer.stop();
    await _vocalsPlayer.stop();
    await _accompanimentPlayer.stop();
  }

  // Play / Pause controls
  Future<void> _togglePlayer(AudioPlayer player, PlayerState state, String path) async {
    if (state == PlayerState.playing) {
      await player.pause();
    } else {
      // Pause other players to prevent clutter
      await _stopAllPlayers();
      await player.play(DeviceFileSource(path));
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasModel = _modelPath != null;
    final hasAudio = _inputAudioPath != null;
    final hasResult = _vocalsAudioPath != null && _accompanimentAudioPath != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F111A), Color(0xFF16192B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 32),

                // Card 1: Model Status
                _buildModelCard(hasModel),
                const SizedBox(height: 20),

                // Card 2: Audio Input Selection
                _buildAudioInputCard(hasAudio),
                const SizedBox(height: 20),

                // Card 3: Hardware Acceleration
                _buildAccelerationCard(),
                const SizedBox(height: 20),

                // Processing / Run Button
                _buildSplitButton(hasModel, hasAudio),
                const SizedBox(height: 28),

                // Card 3: Results & Playback
                if (hasResult) _buildPlaybackCard(),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.music_note_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Splitter AI',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Cross-Platform Vocal Separator',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            )
          ],
        ),
      ],
    );
  }

  Widget _buildModelCard(bool hasModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'AI MODEL (UVR MDX-Net)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                Icon(
                  hasModel ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                  color: hasModel ? Colors.teal : Colors.amber,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasModel) ...[
              const Text(
                'Lightweight UVR model loaded.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Path: ...${path.basename(_modelPath!)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              const Text(
                'Model file is not downloaded yet.',
                style: TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              if (_isDownloadingModel) ...[
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _downloadModel,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download UVR Model (28.3 MB)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioInputCard(bool hasAudio) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INPUT AUDIO',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (hasAudio) ...[
              Text(
                path.basename(_inputAudioPath!),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Path: ${_inputAudioPath!}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              const Text(
                'Select a song (.wav format) or generate synthetic test audio to try immediately.',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickAudioFile,
                    icon: const Icon(Icons.audio_file_outlined, size: 18),
                    label: const Text('Pick WAV'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generateTestAudio,
                    icon: const Icon(Icons.waves_rounded, size: 18),
                    label: const Text('Synthesize L/R'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEC4899)),
                      foregroundColor: const Color(0xFFEC4899),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelerationCard() {
    return Card(
      child: SwitchListTile(
        title: const Text('Hardware Acceleration', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          Platform.isMacOS || Platform.isIOS
              ? 'Use Apple Neural Engine / GPU (CoreML)'
              : Platform.isAndroid
                  ? 'Use Mobile NPU (NNAPI)'
                  : Platform.isWindows
                      ? 'Use GPU Acceleration (DirectML)'
                      : 'Use CPU multi-threading',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        value: _useHardwareAccel,
        activeThumbColor: const Color(0xFF6366F1),
        onChanged: (bool value) {
          setState(() {
            _useHardwareAccel = value;
          });
        },
        secondary: const Icon(Icons.bolt_rounded, color: Colors.amber),
      ),
    );
  }

  Widget _buildSplitButton(bool hasModel, bool hasAudio) {
    final isActive = hasModel && hasAudio && !_isProcessing && !_isDownloadingModel;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: isActive ? _processSeparation : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white10,
          disabledForegroundColor: Colors.white30,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isProcessing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Separating Stems...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : const Text(
                'Separate Vocals & Music',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildPlaybackCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SEPARATED RESULTS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                _buildPlayerControl(
                  title: 'Original Mix',
                  subtitle: 'Both vocals and accompaniment',
                  player: _originalPlayer,
                  state: _originalState,
                  filePath: _inputAudioPath!,
                  duration: _originalDuration,
                  position: _originalPosition,
                  color: const Color(0xFF6366F1),
                ),
                const Divider(height: 32, color: Colors.white10),
                _buildPlayerControl(
                  title: 'Vocals',
                  subtitle: 'Isolated voice',
                  player: _vocalsPlayer,
                  state: _vocalsState,
                  filePath: _vocalsAudioPath!,
                  duration: _vocalsDuration,
                  position: _vocalsPosition,
                  color: const Color(0xFFEC4899),
                ),
                const Divider(height: 32, color: Colors.white10),
                _buildPlayerControl(
                  title: 'Accompaniment',
                  subtitle: 'Instruments and backing track',
                  player: _accompanimentPlayer,
                  state: _accompanimentState,
                  filePath: _accompanimentAudioPath!,
                  duration: _accompanimentDuration,
                  position: _accompanimentPosition,
                  color: Colors.teal,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerControl({
    required String title,
    required String subtitle,
    required AudioPlayer player,
    required PlayerState state,
    required String filePath,
    required Duration duration,
    required Duration position,
    required Color color,
  }) {
    final isPlaying = state == PlayerState.playing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            IconButton.filled(
              onPressed: () => _togglePlayer(player, state, filePath),
              icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              style: IconButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: color,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: color,
                ),
                child: Slider(
                  min: 0.0,
                  max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                  value: min(position.inMilliseconds.toDouble(), duration.inMilliseconds.toDouble()),
                  onChanged: (val) {
                    player.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
            ),
            Text(
              _formatDuration(duration),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}
