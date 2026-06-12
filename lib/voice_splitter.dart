// Copyright (c) 2026 Antigravity
import 'dart:ffi';

import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'src/bindings.dart';
import 'src/wav_helper.dart';

class VoiceSplitterResult {
  final String vocalsPath;
  final String accompanimentPath;
  final int sampleRate;
  final int numSamples;

  VoiceSplitterResult({
    required this.vocalsPath,
    required this.accompanimentPath,
    required this.sampleRate,
    required this.numSamples,
  });

  @override
  String toString() {
    return 'VoiceSplitterResult(vocals: $vocalsPath, accompaniment: $accompanimentPath, sampleRate: $sampleRate, samples: $numSamples)';
  }
}

class VoiceSplitter {
  /// Splits a WAV audio file into vocals and accompaniment using a UVR MDX-Net ONNX model.
  ///
  /// Runs completely in a background isolate to keep the UI smooth.
  ///
  /// Parameters:
  /// - [audioPath]: Absolute path to the input WAV file.
  /// - [modelPath]: Absolute path to the UVR MDX-Net ONNX model file.
  /// - [outVocalsPath]: Optional path for the output vocals WAV file. Defaults to `input_vocals.wav` in the same directory.
  /// - [outAccompanimentPath]: Optional path for the output accompaniment WAV file. Defaults to `input_accompaniment.wav` in the same directory.
  /// - [numThreads]: Number of CPU threads to allocate for inference. Defaults to 4.
  /// - [provider]: Execution provider, defaults to 'cpu'. Can also be 'coreml' (iOS/macOS) or 'nnapi' (Android) if supported by the binary.
  /// - [debug]: Whether to enable verbose debug logging from the native engine.
  /// - [libraryPath]: Optional path to the directory containing the `sherpa-onnx-c-api` native library (useful for desktop deployment).
  static Future<VoiceSplitterResult> split({
    required String audioPath,
    required String modelPath,
    String? outVocalsPath,
    String? outAccompanimentPath,
    int numThreads = 4,
    String provider = 'cpu',
    bool debug = false,
    String? libraryPath,
  }) async {
    // Resolve output paths
    final directory = path.dirname(audioPath);
    final baseName = path.basenameWithoutExtension(audioPath);
    final vocalsPath = outVocalsPath ?? path.join(directory, '${baseName}_vocals.wav');
    final accompanimentPath = outAccompanimentPath ?? path.join(directory, '${baseName}_accompaniment.wav');

    // Run the CPU/inference intensive separation in a background isolate
    return await Isolate.run(() {
      return _splitSync(
        audioPath: audioPath,
        modelPath: modelPath,
        vocalsPath: vocalsPath,
        accompanimentPath: accompanimentPath,
        numThreads: numThreads,
        provider: provider,
        debug: debug,
        libraryPath: libraryPath,
      );
    });
  }

  /// Synchronous implementation meant to run inside a spawned background isolate.
  static VoiceSplitterResult _splitSync({
    required String audioPath,
    required String modelPath,
    required String vocalsPath,
    required String accompanimentPath,
    required int numThreads,
    required String provider,
    required bool debug,
    String? libraryPath,
  }) {
    // 1. Initialize bindings inside this isolate
    VoiceSplitterBindings.init(libraryPath);

    // 2. Read the input WAV file
    final inputWav = WavHelper.read(audioPath);
    final numChannels = inputWav.numChannels;
    final numSamples = inputWav.numSamples;
    final sampleRate = inputWav.sampleRate;

    if (numChannels == 0 || numSamples == 0) {
      throw const FormatException('Input WAV file contains no audio data.');
    }

    // 3. Set up C-API configuration
    final Pointer<Utf8> modelPathPtr = modelPath.toNativeUtf8();
    final Pointer<Utf8> providerPtr = provider.toNativeUtf8();

    final Pointer<SherpaOnnxOfflineSourceSeparationConfig> configPtr =
        calloc<SherpaOnnxOfflineSourceSeparationConfig>();

    // Zero out config (using calloc ensures everything defaults to 0/nullptr)
    configPtr.ref.model.numThreads = numThreads;
    configPtr.ref.model.debug = debug ? 1 : 0;
    configPtr.ref.model.provider = providerPtr;
    configPtr.ref.model.uvr.model = modelPathPtr;

    Pointer<SherpaOnnxOfflineSourceSeparation> enginePtr = nullptr;
    Pointer<Pointer<Float>> samplesPtr = nullptr;
    Pointer<SherpaOnnxSourceSeparationOutput> outputPtr = nullptr;

    try {
      // Create separation engine
      enginePtr = VoiceSplitterBindings.createOfflineSourceSeparation(configPtr);
      if (enginePtr == nullptr) {
        throw Exception(
            'Failed to create SherpaOnnxOfflineSourceSeparation engine. Check model path and config.');
      }

      // Allocate and copy input samples into FFI memory
      samplesPtr = calloc<Pointer<Float>>(numChannels);
      for (int c = 0; c < numChannels; c++) {
        final Pointer<Float> chanPtr = calloc<Float>(numSamples);
        final typedList = chanPtr.asTypedList(numSamples);
        typedList.setAll(0, inputWav.channels[c]);
        samplesPtr[c] = chanPtr;
      }

      // Process separation
      outputPtr = VoiceSplitterBindings.offlineSourceSeparationProcess(
        enginePtr,
        samplesPtr,
        numChannels,
        numSamples,
        sampleRate,
      );

      if (outputPtr == nullptr) {
        throw Exception('Source separation failed during model inference.');
      }

      final numStems = outputPtr.ref.numStems;
      final outSampleRate = outputPtr.ref.sampleRate;

      if (numStems < 2) {
        throw Exception(
            'Model returned $numStems stems, but at least 2 stems (vocals and accompaniment) are required.');
      }

      // Extract stem audio data
      final stems = <List<Float32List>>[];
      for (int s = 0; s < numStems; s++) {
        final stem = outputPtr.ref.stems[s];
        final stemChannels = <Float32List>[];
        for (int c = 0; c < stem.numChannels; c++) {
          final Pointer<Float> chanDataPtr = stem.samples[c];
          final chanList = Float32List(stem.n);
          chanList.setAll(0, chanDataPtr.asTypedList(stem.n));
          stemChannels.add(chanList);
        }
        stems.add(stemChannels);
      }

      // Write results to disk:
      // Stem 0 -> Vocals
      // Stem 1 -> Accompaniment
      WavHelper.write(
        vocalsPath,
        WavData(channels: stems[0], sampleRate: outSampleRate),
      );
      WavHelper.write(
        accompanimentPath,
        WavData(channels: stems[1], sampleRate: outSampleRate),
      );

      return VoiceSplitterResult(
        vocalsPath: vocalsPath,
        accompanimentPath: accompanimentPath,
        sampleRate: outSampleRate,
        numSamples: stems[0].isNotEmpty ? stems[0][0].length : 0,
      );
    } finally {
      // 4. Free all FFI-allocated memory
      calloc.free(modelPathPtr);
      calloc.free(providerPtr);
      calloc.free(configPtr);

      if (enginePtr != nullptr) {
        VoiceSplitterBindings.destroyOfflineSourceSeparation(enginePtr);
      }

      if (samplesPtr != nullptr) {
        for (int c = 0; c < numChannels; c++) {
          if (samplesPtr[c] != nullptr) {
            calloc.free(samplesPtr[c]);
          }
        }
        calloc.free(samplesPtr);
      }

      if (outputPtr != nullptr) {
        VoiceSplitterBindings.destroySourceSeparationOutput(outputPtr);
      }
    }
  }
}
