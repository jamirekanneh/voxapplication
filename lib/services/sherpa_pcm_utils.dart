import 'dart:typed_data';

/// PCM16 little-endian → float32 samples for Sherpa-ONNX.
Float32List pcm16BytesToFloat32(Uint8List bytes, [Endian endian = Endian.little]) {
  final values = Float32List(bytes.length ~/ 2);
  final data = ByteData.view(bytes.buffer);
  for (var i = 0; i < bytes.length; i += 2) {
    final sample = data.getInt16(i, endian);
    values[i ~/ 2] = sample / 32768.0;
  }
  return values;
}

/// Simple RMS energy for voice-activity ducking.
double pcm16Rms(Uint8List bytes, [Endian endian = Endian.little]) {
  if (bytes.length < 2) return 0;
  final data = ByteData.view(bytes.buffer);
  var sum = 0.0;
  final count = bytes.length ~/ 2;
  for (var i = 0; i < bytes.length; i += 2) {
    final sample = data.getInt16(i, endian) / 32768.0;
    sum += sample * sample;
  }
  return count == 0 ? 0 : (sum / count).clamp(0.0, 1.0);
}
