import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_session.dart';
import '../theme_provider.dart';

/// Waits until [FirebaseAuth] matches [userId] before building Firestore streams.
///
/// Querying with a device [userId] without a matching auth session causes
/// permission-denied (brief cache flash, then "Something went wrong").
class FirestoreDataGate extends StatefulWidget {
  const FirestoreDataGate({
    super.key,
    required this.userId,
    required this.builder,
    this.loadingMessage,
  });

  final String userId;
  final Widget Function(BuildContext context) builder;
  final String? loadingMessage;

  @override
  State<FirestoreDataGate> createState() => _FirestoreDataGateState();
}

class _FirestoreDataGateState extends State<FirestoreDataGate> {
  bool _ready = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _syncReady();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    if (!_ready) unawaited(_waitForAuth());
  }

  void _syncReady() {
    _ready = AuthSession.canQueryFirestore(widget.userId);
  }

  void _onAuth(User? user) {
    if (!mounted) return;
    final ok = user != null && user.uid == widget.userId;
    if (ok != _ready) {
      setState(() => _ready = ok);
    }
    if (!ok && !_ready) {
      unawaited(_waitForAuth());
    }
  }

  Future<void> _waitForAuth() async {
    final ok = await AuthSession.waitForAuthMatchingUid(
      widget.userId,
      timeout: const Duration(seconds: 30),
    );
    if (ok && mounted && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  void didUpdateWidget(FirestoreDataGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _syncReady();
      if (!_ready) unawaited(_waitForAuth());
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return widget.builder(context);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: VoxColors.primary(context)),
            const SizedBox(height: 16),
            Text(
              widget.loadingMessage ?? 'Loading your data...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: VoxColors.textSecondary(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Treats permission-denied as "auth not ready yet" — keep waiting, not an error.
bool firestoreSnapshotDenied(Object? error, String expectedUid) {
  if (error == null) return false;
  return error.toString().contains('permission-denied');
}

/// Avoid showing stale offline cache when auth cannot reach the server.
bool firestoreSnapshotCacheOnly(QuerySnapshot snapshot, String expectedUid) {
  return snapshot.metadata.isFromCache &&
      !AuthSession.canQueryFirestore(expectedUid);
}
