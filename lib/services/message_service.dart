import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Messaging: barangay <-> its municipality, and municipality <-> OPPDC.
///
/// threads/{threadId}
///   "brgy_<barangay PSGC>"     = barangay <-> its municipality
///   "mun_<municipality PSGC>"  = municipality <-> OPPDC
///   { type, barangayId (barangay threads only), municipalityId, title,
///     lastMessage, lastType, lastSenderRole, lastAt, unread { <role>: count } }
///
/// threads/{threadId}/messages/{autoId}
///   { senderUid, senderRole, senderName, text, type: 'message' | 'reminder', createdAt }
///
/// Threads are created automatically when the admin adds a municipality or barangay.
/// All sends work offline: they are saved on the phone and sent when internet returns.
class MessageService {
  MessageService({this.onSyncError});

  /// Called if a queued message is rejected by the server later
  final void Function(Object error)? onSyncError;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _threads => _db.collection('threads');

  static String barangayThreadId(String barangayPsgc) => 'brgy_$barangayPsgc';
  static String municipalThreadId(String municipalityPsgc) => 'mun_$municipalityPsgc';

  String? _cachedUid;
  Map<String, dynamic>? _cachedProfile;

  /// The logged-in user's profile (role, displayName), read once and remembered
  Future<Map<String, dynamic>> _me() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not logged in.');
    if (_cachedUid == uid && _cachedProfile != null) return _cachedProfile!;

    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) throw StateError('This account has no profile.');
    _cachedUid = uid;
    _cachedProfile = {'uid': uid, ...snap.data()!};
    return _cachedProfile!;
  }

  /// Who should see the unread badge, given the thread and the sender
  static String _recipientRole(String threadId, String senderRole) {
    if (threadId.startsWith('brgy_')) {
      return senderRole == 'barangay' ? 'municipal' : 'barangay';
    }
    return senderRole == 'municipal' ? 'admin' : 'municipal';
  }

  /// Adds a message to an existing batch (used when returning a submission,
  /// so the status change and the reminder are saved together).
  Future<void> addToBatch(
    WriteBatch batch, {
    required String threadId,
    required String text,
    String type = 'message',
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('Message is empty.');
    if (clean.length > 2000) throw ArgumentError('Message is too long (max 2000 characters).');
    if (type != 'message' && type != 'reminder') {
      throw ArgumentError('Unknown message type: $type');
    }

    final me = await _me();
    final role = me['role'] as String;
    final threadRef = _threads.doc(threadId);

    batch.set(threadRef.collection('messages').doc(), {
      'senderUid': me['uid'],
      'senderRole': role,
      'senderName': me['displayName'] ?? role,
      'text': clean,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(threadRef, {
      'lastMessage': clean.length > 80 ? '${clean.substring(0, 80)}…' : clean,
      'lastType': type,
      'lastSenderRole': role,
      'lastAt': FieldValue.serverTimestamp(),
      'unread.${_recipientRole(threadId, role)}': FieldValue.increment(1),
    });
  }

  /// Sends a normal message, or a reminder ('reminder' is allowed for
  /// municipal users in barangay threads and for OPPDC in municipal threads).
  Future<void> send({
    required String threadId,
    required String text,
    String type = 'message',
  }) async {
    final batch = _db.batch();
    await addToBatch(batch, threadId: threadId, text: text, type: type);
    _commit(batch.commit());
  }

  /// Clears the unread badge for the logged-in user
  Future<void> markRead(String threadId) async {
    final me = await _me();
    _commit(_threads.doc(threadId).update({'unread.${me['role']}': 0}));
  }

  Future<Map<String, dynamic>?> getThread(String threadId) async {
    final snap = await _threads.doc(threadId).get();
    return snap.exists ? {'id': snap.id, ...snap.data()!} : null;
  }

  /// Latest messages, oldest first
  Future<List<Map<String, dynamic>>> getMessages(String threadId, {int limit = 50}) async {
    final snap = await _threads
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList().reversed.toList();
  }

  /// Live chat screen
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String threadId, {int limit = 50}) =>
      _threads
          .doc(threadId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(limit)
          .snapshots();

  /// Municipal inbox: its barangay threads + its OPPDC thread
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMunicipalityThreads(String municipalityPsgc) =>
      _threads.where('municipalityId', isEqualTo: municipalityPsgc).snapshots();

  /// OPPDC inbox: one thread per municipality
  Stream<QuerySnapshot<Map<String, dynamic>>> watchOppdcThreads() =>
      _threads.where('type', isEqualTo: 'municipal').snapshots();

  void _commit(Future<void> write) {
    unawaited(write.catchError((Object e) => onSyncError?.call(e)));
  }
}