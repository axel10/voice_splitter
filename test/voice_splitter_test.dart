import 'package:flutter_test/flutter_test.dart';
import 'package:voice_splitter/voice_splitter.dart';
import 'package:voice_splitter/src/wav_helper.dart';

void main() {
  test('VoiceSplitter throws FileNotFoundException for non-existent files', () async {
    expect(
      () => VoiceSplitter.split(
        audioPath: 'non_existent_file.wav',
        modelPath: 'non_existent_model.onnx',
      ),
      throwsA(isA<FileNotFoundException>()),
    );
  });
}
