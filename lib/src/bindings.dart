// Copyright (c) 2026 Antigravity
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque types
final class SherpaOnnxOfflineSourceSeparation extends Opaque {}

/// Spleeter source-separation model configuration.
final class SherpaOnnxOfflineSourceSeparationSpleeterModelConfig extends Struct {
  external Pointer<Utf8> vocals;
  external Pointer<Utf8> accompaniment;
}

/// UVR (MDX-Net) source-separation model configuration.
final class SherpaOnnxOfflineSourceSeparationUvrModelConfig extends Struct {
  external Pointer<Utf8> model;
}

/// Source-separation model configuration.
final class SherpaOnnxOfflineSourceSeparationModelConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationSpleeterModelConfig spleeter;
  external SherpaOnnxOfflineSourceSeparationUvrModelConfig uvr;
  
  @Int32()
  external int numThreads;
  
  @Int32()
  external int debug;
  
  external Pointer<Utf8> provider;
}

/// Top-level source-separation configuration.
final class SherpaOnnxOfflineSourceSeparationConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationModelConfig model;
}

/// A single stem (one output track) with one or more channels.
final class SherpaOnnxSourceSeparationStem extends Struct {
  /// samples[c] points to the heap-allocated sample array for channel c.
  external Pointer<Pointer<Float>> samples;
  
  @Int32()
  external int numChannels;
  
  @Int32()
  external int n;
}

/// Top-level source-separation output.
final class SherpaOnnxSourceSeparationOutput extends Struct {
  /// Heap-allocated array of stems (length num_stems).
  external Pointer<SherpaOnnxSourceSeparationStem> stems;
  
  @Int32()
  external int numStems;
  
  @Int32()
  external int sampleRate;
}

// C function signatures
typedef CreateOfflineSourceSeparationC = Pointer<SherpaOnnxOfflineSourceSeparation> Function(
  Pointer<SherpaOnnxOfflineSourceSeparationConfig> config,
);
typedef CreateOfflineSourceSeparationDart = Pointer<SherpaOnnxOfflineSourceSeparation> Function(
  Pointer<SherpaOnnxOfflineSourceSeparationConfig> config,
);

typedef DestroyOfflineSourceSeparationC = Void Function(
  Pointer<SherpaOnnxOfflineSourceSeparation> ss,
);
typedef DestroyOfflineSourceSeparationDart = void Function(
  Pointer<SherpaOnnxOfflineSourceSeparation> ss,
);

typedef OfflineSourceSeparationProcessC = Pointer<SherpaOnnxSourceSeparationOutput> Function(
  Pointer<SherpaOnnxOfflineSourceSeparation> ss,
  Pointer<Pointer<Float>> samples,
  Int32 numChannels,
  Int32 numSamples,
  Int32 sampleRate,
);
typedef OfflineSourceSeparationProcessDart = Pointer<SherpaOnnxSourceSeparationOutput> Function(
  Pointer<SherpaOnnxOfflineSourceSeparation> ss,
  Pointer<Pointer<Float>> samples,
  int numChannels,
  int numSamples,
  int sampleRate,
);

typedef DestroySourceSeparationOutputC = Void Function(
  Pointer<SherpaOnnxSourceSeparationOutput> p,
);
typedef DestroySourceSeparationOutputDart = void Function(
  Pointer<SherpaOnnxSourceSeparationOutput> p,
);

class VoiceSplitterBindings {
  static late DynamicLibrary _dylib;
  static bool _initialized = false;

  // Bindings
  static late CreateOfflineSourceSeparationDart createOfflineSourceSeparation;
  static late DestroyOfflineSourceSeparationDart destroyOfflineSourceSeparation;
  static late OfflineSourceSeparationProcessDart offlineSourceSeparationProcess;
  static late DestroySourceSeparationOutputDart destroySourceSeparationOutput;

  static void init([String? path]) {
    if (_initialized) return;

    if (Platform.isMacOS) {
      _dylib = path == null
          ? DynamicLibrary.open('libsherpa-onnx-c-api.dylib')
          : DynamicLibrary.open('$path/libsherpa-onnx-c-api.dylib');
    } else if (Platform.isIOS) {
      _dylib = path == null
          ? DynamicLibrary.open('sherpa_onnx.framework/sherpa_onnx')
          : DynamicLibrary.open('$path/sherpa_onnx.framework/sherpa_onnx');
    } else if (Platform.isAndroid || Platform.isLinux) {
      _dylib = path == null
          ? DynamicLibrary.open('libsherpa-onnx-c-api.so')
          : DynamicLibrary.open('$path/libsherpa-onnx-c-api.so');
    } else if (Platform.isWindows) {
      _dylib = path == null
          ? DynamicLibrary.open('sherpa-onnx-c-api.dll')
          : DynamicLibrary.open('$path\\sherpa-onnx-c-api.dll');
    } else {
      throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
    }

    createOfflineSourceSeparation = _dylib
        .lookup<NativeFunction<CreateOfflineSourceSeparationC>>(
            'SherpaOnnxCreateOfflineSourceSeparation')
        .asFunction();

    destroyOfflineSourceSeparation = _dylib
        .lookup<NativeFunction<DestroyOfflineSourceSeparationC>>(
            'SherpaOnnxDestroyOfflineSourceSeparation')
        .asFunction();

    offlineSourceSeparationProcess = _dylib
        .lookup<NativeFunction<OfflineSourceSeparationProcessC>>(
            'SherpaOnnxOfflineSourceSeparationProcess')
        .asFunction();

    destroySourceSeparationOutput = _dylib
        .lookup<NativeFunction<DestroySourceSeparationOutputC>>(
            'SherpaOnnxDestroySourceSeparationOutput')
        .asFunction();

    _initialized = true;
  }
}
