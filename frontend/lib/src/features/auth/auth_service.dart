import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // 1. 구글 로그인 (로그인만 함, 프로필 생성 X)
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase 로그인
      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      return userCredential.user;
    } catch (e) {
      print("❌ 구글 로그인 에러: $e");
      rethrow;
    }
  }

  // 1-2. 애플 로그인 (로그인만 함)
  Future<User?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthCredential credential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      return userCredential.user;
    } catch (e) {
      print("❌ 애플 로그인 에러: $e");
      rethrow;
    }
  }

  // 2. 로그아웃
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      // 구글 로그인 안 한 상태면 에러 날 수 있음 (무시)
    }
    await _auth.signOut();
  }

  // ★ [복구됨] 3. 회원 탈퇴 (완벽한 정리)
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;

    try {
      // (1) 작성한 주제(게시글) 삭제
      final topicsSnapshot = await _db
          .collection('topics')
          .where('authorId', isEqualTo: userId)
          .get();

      for (var topicDoc in topicsSnapshot.docs) {
        await topicDoc.reference.delete();
      }

      // (2) 작성한 댓글 삭제
      final allTopicsSnapshot = await _db.collection('topics').get();

      for (var topicDoc in allTopicsSnapshot.docs) {
        final commentsSnapshot = await _db
            .collection('topics')
            .doc(topicDoc.id)
            .collection('comments')
            .where('uid', isEqualTo: userId)
            .get();

        for (var commentDoc in commentsSnapshot.docs) {
          await commentDoc.reference.delete();
        }

        // 대댓글 제거 로직
        final allCommentsSnapshot = await _db
            .collection('topics')
            .doc(topicDoc.id)
            .collection('comments')
            .get();

        for (var commentDoc in allCommentsSnapshot.docs) {
          final commentData = commentDoc.data();
          final replies = commentData['replies'] as List<dynamic>? ?? [];
          bool hasUpdated = false;
          final updatedReplies = replies.where((reply) {
            final replyData = reply as Map<String, dynamic>;
            if (replyData['uid'] == userId) {
              hasUpdated = true;
              return false;
            }
            return true;
          }).toList();

          if (hasUpdated) {
            await commentDoc.reference.update({'replies': updatedReplies});
          }
        }
      }

      // (3) 투표 정보 삭제
      final votesSnapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('votes')
          .get();

      for (var voteDoc in votesSnapshot.docs) {
        await voteDoc.reference.delete();
      }

      // (4) Firestore 유저 데이터 삭제
      await _db.collection('users').doc(userId).delete();

      // (5) Firebase Auth 계정 삭제
      await user.delete();

      // (6) 로컬 정리
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      await _auth.signOut();
    } catch (e) {
      print("❌ 회원 탈퇴 실패: $e");
      rethrow;
    }
  }

  // ★ [NEW] 프로필이 이미 존재하는지 확인하는 함수
  Future<bool> hasProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  // ★ [NEW] 닉네임을 받아서 프로필을 만드는 함수 (화면에서 호출)
  Future<void> createProfile(User user, String nickname) async {
    // 닉네임 중복 체크
    final query = await _db
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      throw Exception('이미 사용 중인 닉네임입니다.');
    }

    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'nickname': nickname,
      'photoUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
      'isPublic': true,
    });
  }

  // ★ [NEW] 유저 제재 상태 확인 및 처리
  /// 제재된 유저인지 확인하고, 제재된 경우 강제 로그아웃 처리
  /// 
  /// [uid] 확인할 유저의 UID
  /// 
  /// 반환값: true = 정상 유저, false = 제재된 유저 (로그아웃 처리됨)
  /// 
  /// 제재 조건:
  /// - isBanned == true
  /// - warningCount >= 3
  Future<bool> checkUserStatus(String uid) async {
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      
      if (!userDoc.exists) {
        // 프로필이 없으면 정상 처리 (신규 유저)
        return true;
      }

      final userData = userDoc.data();
      if (userData == null) {
        return true;
      }

      final isBanned = userData['isBanned'] as bool? ?? false;
      final warningCount = userData['warningCount'] as int? ?? 0;

      // 제재 조건 확인
      if (isBanned || warningCount >= 3) {
        // 제재된 유저: 강제 로그아웃
        print('🚫 제재된 유저 감지: uid=$uid, isBanned=$isBanned, warningCount=$warningCount');
        await signOut();
        return false;
      }

      // 정상 유저
      return true;
    } catch (e) {
      print('❌ 유저 상태 확인 에러: $e');
      // 에러 발생 시 안전하게 정상 유저로 처리
      return true;
    }
  }
}
