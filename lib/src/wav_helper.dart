// Copyright (c) 2026 Antigravity
import 'dart:io';
import 'dart:typed_data';

class WavData {
  final List<Float32List> channels;
  final int sampleRate;

  WavData({required this.channels, required this.sampleRate});

  int get numChannels => channels.length;
  int get numSamples => channels.isNotEmpty ? channels[0].length : 0;
}

class WavHelper {
  /// Reads a WAV file (16-bit signed PCM or 32-bit Float PCM, mono or stereo) and normalizes it to [-1.0, 1.0].
  static WavData read(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileNotFoundException(filePath);
    }

    final bytes = file.readAsBytesSync();
    final byteData = ByteData.sublistView(bytes);

    // Verify RIFF and WAVE headers
    if (bytes.length < 44) {
      throw const FormatException('File is too short to be a valid WAV file');
    }

    final riffStr = _readString(byteData, 0, 4);
    final waveStr = _readString(byteData, 8, 4);

    if (riffStr != 'RIFF' || waveStr != 'WAVE') {
      throw const FormatException('Invalid WAV file header');
    }

    int offset = 12;
    int numChannels = 0;
    int sampleRate = 0;
    int bitsPerSample = 0;
    int audioFormat = 0;
    int dataOffset = 0;
    int dataSize = 0;

    // Parse chunks
    while (offset < bytes.length - 8) {
      final chunkId = _readString(byteData, offset, 4);
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        audioFormat = byteData.getUint16(offset, Endian.little); // 1 = PCM, 3 = IEEE Float
        numChannels = byteData.getUint16(offset + 2, Endian.little);
        sampleRate = byteData.getUint32(offset + 4, Endian.little);
        bitsPerSample = byteData.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset;
        dataSize = chunkSize;
      }
      offset += chunkSize;
    }

    if (numChannels == 0 || sampleRate == 0 || bitsPerSample == 0) {
      throw const FormatException('Required fmt chunk fields are missing');
    }

    if (dataOffset == 0) {
      throw const FormatException('data chunk is missing');
    }

    if (audioFormat != 1 && audioFormat != 3) {
      throw FormatException('Unsupported audio format: $audioFormat (only PCM and IEEE Float are supported)');
    }

    if (bitsPerSample != 16 && bitsPerSample != 32) {
      throw FormatException('Unsupported bits per sample: $bitsPerSample (only 16-bit and 32-bit are supported)');
    }

    // Read sample data
    final bytesPerSample = bitsPerSample ~/ 8;
    final totalSamples = dataSize ~/ bytesPerSample;
    final numFrames = totalSamples ~/ numChannels;

    final channels = List<Float32List>.generate(
      numChannels,
      (_) => Float32List(numFrames),
    );

    int sampleOffset = dataOffset;

    if (audioFormat == 1 && bitsPerSample == 16) {
      // 16-bit Signed Integer PCM
      for (int i = 0; i < numFrames; i++) {
        for (int c = 0; c < numChannels; c++) {
          if (sampleOffset + 2 > bytes.length) break;
          final val = byteData.getInt16(sampleOffset, Endian.little);
          channels[c][i] = val / 32768.0;
          sampleOffset += 2;
        }
      }
    } else if (audioFormat == 3 && bitsPerSample == 32) {
      // 32-bit Float PCM
      for (int i = 0; i < numFrames; i++) {
        for (int c = 0; c < numChannels; c++) {
          if (sampleOffset + 4 > bytes.length) break;
          final val = byteData.getFloat32(sampleOffset, Endian.little);
          channels[c][i] = val;
          sampleOffset += 4;
        }
      }
    } else if (audioFormat == 1 && bitsPerSample == 32) {
      // 32-bit Signed Integer PCM
      for (int i = 0; i < numFrames; i++) {
        for (int c = 0; c < numChannels; c++) {
          if (sampleOffset + 4 > bytes.length) break;
          final val = byteData.getInt32(sampleOffset, Endian.little);
          channels[c][i] = val / 2147483648.0;
          sampleOffset += 4;
        }
      }
    }

    return WavData(channels: channels, sampleRate: sampleRate);
  }

  /// Writes a WAV file (16-bit signed PCM) from normalized [-1.0, 1.0] samples.
  static void write(String filePath, WavData wavData) {
    final numChannels = wavData.numChannels;
    final numFrames = wavData.numSamples;
    final sampleRate = wavData.sampleRate;
    const bitsPerSample = 16;
    final bytesPerSample = bitsPerSample ~/ 8;

    final dataSize = numFrames * numChannels * bytesPerSample;
    final fileSize = 36 + dataSize;

    final bytes = Uint8List(44 + dataSize);
    final byteData = ByteData.sublistView(bytes);

    // RIFF Chunk
    _writeString(byteData, 0, 'RIFF');
    byteData.setUint32(4, fileSize, Endian.little);
    _writeString(byteData, 8, 'WAVE');

    // fmt Chunk
    _writeString(byteData, 12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little); // Chunk size
    byteData.setUint16(20, 1, Endian.little);  // Audio format (1 = PCM)
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    
    final byteRate = sampleRate * numChannels * bytesPerSample;
    byteData.setUint32(28, byteRate, Endian.little);
    
    final blockAlign = numChannels * bytesPerSample;
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // data Chunk
    _writeString(byteData, 36, 'data');
    byteData.setUint32(40, dataSize, Endian.little);

    // Interleave and scale samples to 16-bit integers
    int offset = 44;
    for (int i = 0; i < numFrames; i++) {
      for (int c = 0; c < numChannels; c++) {
        final floatSample = wavData.channels[c][i];
        
        // Clamp to [-1.0, 1.0] to prevent overflow
        final clampedVal = floatSample.clamp(-1.0, 1.0);
        final intSample = (clampedVal * 32767.0).round();
        
        byteData.setInt16(offset, intSample, Endian.little);
        offset += 2;
      }
    }

    final file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  static String _readString(ByteData data, int offset, int length) {
    final codes = List<int>.generate(length, (i) => data.getUint8(offset + i));
    return String.fromCharCodes(codes);
  }

  static void _writeString(ByteData data, int offset, String str) {
    for (int i = 0; i < str.length; i++) {
      data.setUint8(offset + i, str.codeUnitAt(i));
    }
  }
}

class FileNotFoundException implements Exception {
  final String path;
  FileNotFoundException(this.path);

  @override
  String toString() => "FileNotFoundException: The file '$path' could not be found.";
}
