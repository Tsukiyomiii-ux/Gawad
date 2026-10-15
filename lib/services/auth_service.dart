import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

/// Login and account creation for Gawad.
///
/// MVP only: login IDs are turned into fake emails,
/// e.g. "brgy-ungka1" -> "brgy-ungka1@gawad.app".
///
/// municipalityId and barangayId are the official 10-digit PSGC codes.
///
/// STAYING SIGNED IN
///   The first sign-in on a phone needs internet. After that the user stays
///   signed in (also offline) until signOut() is called. Call restoreSession()
///   when the app starts to skip the login screen.
///
/// FORGOT PASSWORD
///   The fake emails cannot receive reset emails, so resets go through OPPDC:
///   1. Login screen: requestPasswordReset(loginId)  -> request goes to OPPDC
///   2. OPPDC: deletes the old login in Firebase Console -> Authentication
///   3. OPPDC app: resetAccount(loginId, temporaryPassword) -> same login ID,
///      same municipality/barangay, new temporary password
///   4. User logs in with the temporary password, then changePassword(...)
class AuthService {
  static const String _emailDomain = 'gawad.app';
  static const List<String> roles = ['admin', 'municipal', 'barangay'];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _resetRequests =>
      _db.collection('passwordResetRequests');

  static String toEmail(String loginId) =>
      '${loginId.trim().toLowerCase()}@$_emailDomain';

  User? get currentUser => _auth.currentUser;

  // =====================================================================
  // SIGN IN / STAY SIGNED IN / SIGN OUT
  // =====================================================================

  /// Logs in (needs internet the first time on a phone) and returns the profile:
  /// role, displayName, municipalityId, barangayId.
  Future<Map<String, dynamic>> signIn(String loginId, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: toEmail(loginId),
      password: password,
    );

    final profile = await _users.doc(cred.user!.uid).get();
    if (!profile.exists) {
      await _auth.signOut();
      throw StateError('This account has no profile in "users". Ask the admin.');
    }
    return profile.data()!;
  }

  /// Call once when the app starts.
  /// Returns the profile if someone is still signed in on this phone,
  /// or null (show the login screen). Works offline after the first sign-in.
  Future<Map<String, dynamic>?> restoreSession() async {
    // On app start Firebase may need a moment to load the saved login
    final user = _auth.currentUser ?? await _auth.authStateChanges().first;
    if (user == null) return null;

    try {
      final snap = await _users.doc(user.uid).get();
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null; // offline and never loaded before
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Logged-in user changes their own password, e.g. after getting a
  /// temporary password from OPPDC. Needs internet.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not logged in.');
    if (newPassword.length < 6) {
      throw ArgumentError('New password must be at least 6 characters.');
    }
    try {
      // Firebase asks for the current password again before a change
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw StateError('Your current password is wrong.');
      }
      rethrow;
    }
  }

  // =====================================================================
  // FORGOT PASSWORD (through OPPDC)
  // =====================================================================

  /// Login screen, not logged in: sends a reset request to OPPDC.
  /// Needs internet.
  Future<void> requestPasswordReset(String loginId, {String note = ''}) async {
    final id = loginId.trim().toLowerCase();
    if (id.isEmpty) throw ArgumentError('Type your login ID first.');
    if (note.trim().length > 300) throw ArgumentError('Note is too long (max 300 characters).');

    try {
      await _resetRequests.add({
        'loginId': id,
        'note': note.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw StateError('No internet connection. Connect and try again.');
    }
  }

  /// OPPDC: pending reset requests, oldest first
  Future<List<Map<String, dynamic>>> getPendingResetRequests() async {
    final snap = await _resetRequests.where('status', isEqualTo: 'pending').get();
    final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    list.sort((a, b) {
      final ta = a['createdAt'] as Timestamp?;
      final tb = b['createdAt'] as Timestamp?;
      if (ta == null || tb == null) return 0;
      return ta.compareTo(tb);
    });
    return list;
  }

  /// OPPDC: gives an account a new temporary password.
  ///
  /// FIRST delete the old login in Firebase Console -> Authentication -> Users
  /// (the email shown there is "<loginId>@gawad.app"). Firebase does not let an
  /// app change someone else's password on the free plan, so the login is
  /// re-created with the same login ID, role, municipality and barangay.
  /// All records (tanods, archives, statuses) are kept.
  Future<void> resetAccount({
    required String loginId,
    required String temporaryPassword,
    String? requestId,
  }) async {
    final id = loginId.trim().toLowerCase();
    if (temporaryPassword.length < 6) {
      throw ArgumentError('Temporary password must be at least 6 characters.');
    }

    final found = await _users.where('loginId', isEqualTo: id).limit(1).get();
    if (found.docs.isEmpty) throw StateError('No account with login ID "$id".');
    final oldDoc = found.docs.first;
    final old = oldDoc.data();
    if (old['role'] == 'admin') {
      throw StateError('The admin account cannot be reset from the app.');
    }

    final String newUid;
    try {
      newUid = await _createLogin(id, temporaryPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw StateError('The old login still exists. First delete ${toEmail(id)} in '
            'Firebase Console -> Authentication -> Users, then try again.');
      }
      rethrow;
    }

    final batch = _db.batch();
    batch.set(_users.doc(newUid), {
      ...old,
      'passwordResetAt': FieldValue.serverTimestamp(),
    });
    batch.delete(oldDoc.reference);
    if (requestId != null) {
      batch.update(_resetRequests.doc(requestId), {
        'status': 'done',
        'doneAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// OPPDC: closes a request without resetting (e.g. a wrong login ID)
  Future<void> dismissResetRequest(String requestId) => _resetRequests.doc(requestId).update({
        'status': 'dismissed',
        'doneAt': FieldValue.serverTimestamp(),
      });

  // =====================================================================
  // CREATING ACCOUNTS (OPPDC)
  // =====================================================================

  /// Admin only: creates a municipal or barangay account WITHOUT logging the admin out.
  ///
  /// Normally createUserWithEmailAndPassword switches the app to the new user.
  /// To avoid that, the account is created on a second Firebase app instance,
  /// so the admin's own session is never touched. Works on the free Spark plan.
  Future<String> createAccount({
    required String loginId,
    required String password,
    required String role,
    required String displayName,
    String? municipalityId,
    String? barangayId,
  }) async {
    if (!roles.contains(role)) throw ArgumentError('Unknown role: $role');
    if (role != 'admin' && municipalityId == null) {
      throw ArgumentError('$role accounts need a municipalityId');
    }
    if (role == 'barangay' && barangayId == null) {
      throw ArgumentError('barangay accounts need a barangayId');
    }
    if (password.length < 6) {
      throw ArgumentError('Password must be at least 6 characters (Firebase rule)');
    }

    // Make sure the place exists before making an account for it
    if (municipalityId != null) {
      final mun = await _db.collection('municipalities').doc(municipalityId).get();
      if (!mun.exists) throw StateError('Municipality $municipalityId does not exist yet.');
    }
    if (barangayId != null) {
      final brgy = await _db.collection('barangays').doc(barangayId).get();
      if (!brgy.exists) throw StateError('Barangay $barangayId does not exist yet.');
      if (brgy.data()!['municipalityId'] != municipalityId) {
        throw StateError('Barangay $barangayId is not in municipality $municipalityId.');
      }
    }

    final uid = await _createLogin(loginId, password);

    // The profile is written by the admin's own session (rules only let admins write users)
    await _users.doc(uid).set({
      'loginId': loginId.trim().toLowerCase(),
      'role': role,
      'displayName': displayName,
      'municipalityId': municipalityId,
      'barangayId': barangayId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return uid;
  }

  /// Creates the Firebase login on a second app instance (admin stays logged in)
  Future<String> _createLogin(String loginId, String password) async {
    FirebaseApp secondary;
    try {
      secondary = Firebase.app('accountCreator');
    } catch (_) {
      secondary = await Firebase.initializeApp(
        name: 'accountCreator',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
    final cred = await secondaryAuth.createUserWithEmailAndPassword(
      email: toEmail(loginId),
      password: password,
    );
    final uid = cred.user!.uid;
    await secondaryAuth.signOut();
    return uid;
  }
}