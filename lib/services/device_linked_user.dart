/// User last associated with this physical device (from Firestore `devices` doc).
class DeviceLinkedUser {
  final String userId;
  final String? email;
  final String? username;

  const DeviceLinkedUser({
    required this.userId,
    this.email,
    this.username,
  });
}
