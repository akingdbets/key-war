import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 신고하기
  /// 
  /// [targetId] 신고 대상의 ID (Topic ID 또는 Comment ID)
  /// [targetType] 'topic' 또는 'comment'
  /// [reason] 신고 사유
  /// [topicId] 댓글 신고 시 주제 ID (댓글의 경우 필수)
  /// 
  /// 반환값: 성공 여부
  Future<bool> report({
    required String targetId,
    required String targetType,
    required String reason,
    String? topicId,
  }) async {
    // 로그인 확인
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    // targetType 검증
    if (targetType != 'topic' && targetType != 'comment') {
      throw Exception('유효하지 않은 신고 대상 타입입니다.');
    }

    // 댓글 신고 시 topicId 필수
    if (targetType == 'comment' && topicId == null) {
      throw Exception('댓글 신고 시 주제 ID가 필요합니다.');
    }

    // 중복 신고 체크
    final existingReport = await _db
        .collection('reports')
        .where('reporterId', isEqualTo: user.uid)
        .where('targetId', isEqualTo: targetId)
        .where('targetType', isEqualTo: targetType)
        .limit(1)
        .get();

    if (existingReport.docs.isNotEmpty) {
      throw Exception('이미 신고한 항목입니다.');
    }

    // 신고 저장 및 reportCount 증가 처리
    // 주의: Transaction 대신 일반 업데이트 사용 (보안 규칙 문제 해결)
    try {
      // 1. 대상 문서 참조 생성
      DocumentReference targetRef;
      if (targetType == 'topic') {
        targetRef = _db.collection('topics').doc(targetId);
      } else {
        // 댓글의 경우: topics/{topicId}/comments/{commentId}
        if (topicId == null) {
          throw Exception('댓글 신고 시 주제 ID가 필요합니다.');
        }
        targetRef = _db
            .collection('topics')
            .doc(topicId)
            .collection('comments')
            .doc(targetId);
      }

      // 2. 대상 문서 읽기
      final targetDoc = await targetRef.get();
      if (!targetDoc.exists) {
        throw Exception('신고 대상이 존재하지 않습니다.');
      }

      final targetData = targetDoc.data();
      if (targetData == null) {
        throw Exception('신고 대상 데이터를 불러올 수 없습니다.');
      }

      final dataMap = targetData as Map<String, dynamic>;
      final currentReportCount = dataMap['reportCount'] as int? ?? 0;
      final newReportCount = currentReportCount + 1;

      // 3. reportCount 업데이트 데이터 준비
      final updateData = <String, dynamic>{
        'reportCount': newReportCount,
      };

      // reportCount가 3 이상이면 'review' 상태로 변경
      if (newReportCount >= 3) {
        updateData['status'] = 'review';
        updateData['isUnderReview'] = true;
      }

      // 4. 신고 저장 및 대상 문서 업데이트 (병렬 처리)
      await Future.wait([
        // 4-1. 신고 저장
        _db.collection('reports').add({
          'reporterId': user.uid,
          'targetId': targetId,
          'targetType': targetType,
          'reason': reason,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        }),
        // 4-2. 대상 문서 업데이트
        targetRef.update(updateData),
      ]);

      return true;
    } catch (e) {
      print('❌ 신고 저장 에러: $e');
      throw Exception('신고 처리 중 오류가 발생했습니다: ${e.toString()}');
    }
  }

  /// 중복 신고 여부 확인
  Future<bool> hasReported({
    required String targetId,
    required String targetType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final existingReport = await _db
        .collection('reports')
        .where('reporterId', isEqualTo: user.uid)
        .where('targetId', isEqualTo: targetId)
        .where('targetType', isEqualTo: targetType)
        .limit(1)
        .get();

    return existingReport.docs.isNotEmpty;
  }
}

