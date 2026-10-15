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
class AuthService {
  static const String _emailDomain = 'gawad.app';
  static const List<String> roles = ['admin', 'municipal', 'barangay'];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String toEmail(String loginId) =>
      '${loginId.trim().toLowerCase()}@$_emailDomain';

  User? get currentUser => _auth.currentUser;

  /// Logs in (needs internet the first time on a phone) and returns the profile:
  /// role, displayName, municipalityId, barangayId.
  Future<Map<String, dynamic>> signIn(String loginId, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: toEmail(loginId),
      password: password,
    );

    final profile = await _db.collection('users').doc(cred.user!.uid).get();
    if (!profile.exists) {
      await _auth.signOut();
      throw StateError('This account has no profile in "users". Ask the admin.');
    }
    return profile.data()!;
  }

  /// When the app reopens, returns the profile of whoever is still logged in
  /// on this phone. Works offline. Returns null if nobody is logged in.
  Future<Map<String, dynamic>?> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final snap = await _db.collection('users').doc(user.uid).get();
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null; // offline and never loaded before
    }
  }

  Future<void> signOut() => _auth.signOut();

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

    // Reuse the second app if it was already created earlier
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

    // The profile is written by the admin's own session (rules only let admins write users)
    await _db.collection('users').doc(uid).set({
      'loginId': loginId.trim().toLowerCase(),
      'role': role,
      'displayName': displayName,
      'municipalityId': municipalityId,
      'barangayId': barangayId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return uid;
  }
}