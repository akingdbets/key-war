import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BlockService {
  // 1. 싱글톤 인스턴스 생성 (앱 전체에서 공유)
  static final BlockService instance = BlockService._internal();

  factory BlockService() => instance;

  BlockService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 2. 내부 상태 관리 (메모리 캐시)
  List<String> _blockedUserIds = [];

  // 3. 실시간 업데이트를 위한 스트림 컨트롤러
  final StreamController<List<String>> _blockedUsersController =
      StreamController<List<String>>.broadcast();

  // 외부에서 구독할 스트림
  Stream<List<String>> get blockedUsersStream => _blockedUsersController.stream;

  // 현재 차단 목록 바로 가져오기 (동기적 접근)
  List<String> get currentBlockedUsers => _blockedUserIds;

  /// 초기화: 앱 실행 시(main.dart 또는 로그인 직후) 한 번 호출
  Future<void> init() async {
    final user = _auth.currentUser;
    if (user == null) {
      _blockedUserIds = [];
      _blockedUsersController.add([]);
      return;
    }

    // Firestore의 실시간 리스너 연결
    _db.collection('users').doc(user.uid).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        final blockedList = List<String>.from(data?['blockedUsers'] ?? []);

        // 내부 데이터 업데이트 및 방송
        _blockedUserIds = blockedList;
        _blockedUsersController.add(_blockedUserIds);
      } else {
        _blockedUserIds = [];
        _blockedUsersController.add([]);
      }
    });
  }

  /// 사용자 차단하기 (즉시 반영)
  Future<bool> blockUser(String blockedUserId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    if (user.uid == blockedUserId) throw Exception('자기 자신을 차단할 수 없습니다.');

    // 1. 낙관적 업데이트 (서버 응답 기다리지 않고 UI 즉시 갱신)
    if (!_blockedUserIds.contains(blockedUserId)) {
      _blockedUserIds.add(blockedUserId);
      _blockedUsersController.add(_blockedUserIds); // 화면 갱신 신호 보냄
    }

    try {
      // 2. Firestore에 저장
      await _db.collection('users').doc(user.uid).update({
        'blockedUsers': FieldValue.arrayUnion([blockedUserId]),
      });

      // 3. 차단한 사용자의 게시물 삭제 (Soft Delete)
      try {
        final topicsSnapshot = await _db
            .collection('topics')
            .where('authorId', isEqualTo: blockedUserId)
            .get();

        final batch = _db.batch();
        for (var topicDoc in topicsSnapshot.docs) {
          batch.update(topicDoc.reference, {'status': 'deleted'});
        }
        if (topicsSnapshot.docs.isNotEmpty) {
          await batch.commit();
          print('✅ 차단한 사용자의 게시물 ${topicsSnapshot.docs.length}개 삭제 완료');
        }
      } catch (e) {
        print('⚠️ 게시물 삭제 중 오류 (무시): $e');
      }

      // 4. 차단한 사용자의 댓글 삭제 (Soft Delete)
      try {
        final allTopicsSnapshot = await _db.collection('topics').get();
        int deletedCommentsCount = 0;

        for (var topicDoc in allTopicsSnapshot.docs) {
          final commentsSnapshot = await _db
              .collection('topics')
              .doc(topicDoc.id)
              .collection('comments')
              .where('uid', isEqualTo: blockedUserId)
              .get();

          final batch = _db.batch();
          for (var commentDoc in commentsSnapshot.docs) {
            batch.update(commentDoc.reference, {
              'isDeleted': true,
              'content': '삭제된 댓글입니다',
              'author': '알 수 없음',
            });
            deletedCommentsCount++;
          }
          if (commentsSnapshot.docs.isNotEmpty) {
            await batch.commit();
          }

          // 대댓글도 삭제
          final allCommentsSnapshot = await _db
              .collection('topics')
              .doc(topicDoc.id)
              .collection('comments')
              .get();

          final replyBatch = _db.batch();
          bool hasReplyUpdates = false;
          for (var commentDoc in allCommentsSnapshot.docs) {
            final commentData = commentDoc.data();
            final replies = commentData['replies'] as List<dynamic>? ?? [];
            final updatedReplies = replies.map((reply) {
              final replyData = reply as Map<String, dynamic>;
              if (replyData['uid'] == blockedUserId) {
                hasReplyUpdates = true;
                return {
                  ...replyData,
                  'content': '삭제된 댓글입니다',
                  'author': '알 수 없음',
                  'isDeleted': true,
                };
              }
              return reply;
            }).toList();

            if (hasReplyUpdates) {
              replyBatch.update(commentDoc.reference, {'replies': updatedReplies});
              deletedCommentsCount++;
            }
          }
          if (hasReplyUpdates) {
            await replyBatch.commit();
          }
        }
        if (deletedCommentsCount > 0) {
          print('✅ 차단한 사용자의 댓글 $deletedCommentsCount개 삭제 완료');
        }
      } catch (e) {
        print('⚠️ 댓글 삭제 중 오류 (무시): $e');
      }

      // 5. 차단한 사용자와 관련된 알림 삭제
      try {
        final notificationsSnapshot = await _db
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .where('senderId', isEqualTo: blockedUserId)
            .get();

        final batch = _db.batch();
        for (var notificationDoc in notificationsSnapshot.docs) {
          batch.delete(notificationDoc.reference);
        }
        if (notificationsSnapshot.docs.isNotEmpty) {
          await batch.commit();
          print('✅ 차단한 사용자 관련 알림 ${notificationsSnapshot.docs.length}개 삭제 완료');
        }
      } catch (e) {
        print('⚠️ 알림 삭제 중 오류 (무시): $e');
      }

      return true;
    } catch (e) {
      print('❌ 사용자 차단 에러: $e');
      // 실패 시 롤백
      _blockedUserIds.remove(blockedUserId);
      _blockedUsersController.add(_blockedUserIds);
      throw Exception('차단 실패: ${e.toString()}');
    }
  }

  /// 사용자 차단 해제하기 (즉시 반영)
  Future<bool> unblockUser(String blockedUserId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');

    // 1. 낙관적 업데이트
    if (_blockedUserIds.contains(blockedUserId)) {
      _blockedUserIds.remove(blockedUserId);
      _blockedUsersController.add(_blockedUserIds); // 화면 갱신 신호 보냄
    }

    try {
      // 2. Firestore 업데이트
      await _db.collection('users').doc(user.uid).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUserId]),
      });
      return true;
    } catch (e) {
      print('❌ 사용자 차단 해제 에러: $e');
      // 실패 시 롤백 (다시 추가)
      _blockedUserIds.add(blockedUserId);
      _blockedUsersController.add(_blockedUserIds);
      throw Exception('차단 해제 실패: ${e.toString()}');
    }
  }

  /// 특정 사용자가 차단된 상태인지 확인
  bool isUserBlocked(String userId) {
    return _blockedUserIds.contains(userId);
  }

  void dispose() {
    _blockedUsersController.close();
  }
}
