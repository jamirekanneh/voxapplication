import 'package:hive/hive.dart';
class QueuedRecording extends HiveObject {
  late String filePath;
  late int durationSeconds;
  late String uid;
  late int timestamp; // milliseconds since epoch
  late String status; // 'pending', 'completed', 'failed'
  late int attempts; // number of upload attempts
}

class QueuedRecordingAdapter extends TypeAdapter<QueuedRecording> {
  @override
  final int typeId = 0;

  @override
  QueuedRecording read(BinaryReader reader) {
    final rec = QueuedRecording();
    rec.filePath = reader.readString();
    rec.durationSeconds = reader.readInt();
    rec.uid = reader.readString();
    rec.timestamp = reader.readInt();
    rec.status = reader.readString();
    rec.attempts = reader.readInt();
    return rec;
  }

  @override
  void write(BinaryWriter writer, QueuedRecording obj) {
    writer.writeString(obj.filePath);
    writer.writeInt(obj.durationSeconds);
    writer.writeString(obj.uid);
    writer.writeInt(obj.timestamp);
    writer.writeString(obj.status);
    writer.writeInt(obj.attempts);
  }
}
