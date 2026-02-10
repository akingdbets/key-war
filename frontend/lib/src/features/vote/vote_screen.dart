import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../profile/profile_screen.dart';
import '../report/report_service.dart';
import '../report/report_dialog.dart';
import '../block/block_service.dart'; // ★ BlockService import
import '../../utils/notification_state.dart';
import '../../utils/profanity_filter.dart';

// 원댓글이 삭제되었을 때 발생하는 예외
class ParentCommentDeletedException implements Exception {
  final String message;
  ParentCommentDeletedException(this.message);

  @override
  String toString() => message;
}

class VoteScreen extends StatefulWidget {
  final String topicId; // 주제 ID (필수)
  final String? highlightComment; // 베스트 댓글 하이라이트용 (선택)

  const VoteScreen({super.key, required this.topicId, this.highlightComment});

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen>
    with AutomaticKeepAliveClientMixin {
  // ★ 파이어베이스 DB 및 서비스 인스턴스
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ReportService _reportService = ReportService();
  final BlockService _blockService = BlockService.instance; // ★ 싱글톤 사용

  int? _selectedOptionIndex; // 낙관적 업데이트용 (즉시 UI 반영)
  int? _confirmedOptionIndex; // 서버에 확실히 저장된 투표 상태
  Map<int, int> _optimisticTargets = {}; // 목표값 고정
  List<int> _currentServerCounts = []; // 현재 서버 투표수
  String _commentSort = '최신순';

  // 대댓글 관련 상태
  String? _replyingToDocId;

  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Color> _optionColors = [
    Colors.blueAccent,
    Colors.redAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
  ];

  double _savedScrollPosition = 0.0;
  bool _isNavigating = false;

  // Stream 변수
  Stream<DocumentSnapshot>? _topicStream;
  Stream<QuerySnapshot>? _commentsStream;

  // 로컬 상태 관리
  final Set<String> _reportedComments = {};
  bool _isTopicReported = false;
  String? _topicAuthorId; // 주제 작성자 ID (차단 기능을 위해 필요)

  Timer? _voteDebounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    NotificationState.setCurrentViewingVoteId(widget.topicId);

    // Stream 초기화
    _topicStream = _db.collection('topics').doc(widget.topicId).snapshots();
    _commentsStream = _db
        .collection('topics')
        .doc(widget.topicId)
        .collection('comments')
        .snapshots();

    _loadUserVote();
    _loadReportedItems();
    _fetchTopicAuthor(); // 주제 작성자 ID 가져오기

    _scrollController.addListener(_onScroll);
    _commentFocusNode.addListener(_onFocusChange);
  }

  // 주제 작성자 ID 가져오기 (메뉴에서 차단하기 위해)
  Future<void> _fetchTopicAuthor() async {
    try {
      final doc = await _db.collection('topics').doc(widget.topicId).get();
      if (doc.exists && mounted) {
        setState(() {
          _topicAuthorId = doc.data()?['authorId'] ?? doc.data()?['uid'];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReportedItems() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final topicReports = await _db
          .collection('reports')
          .where('reporterId', isEqualTo: user.uid)
          .where('targetId', isEqualTo: widget.topicId)
          .where('targetType', isEqualTo: 'topic')
          .limit(1)
          .get();

      if (topicReports.docs.isNotEmpty && mounted) {
        setState(() => _isTopicReported = true);
      }

      final commentReports = await _db
          .collection('reports')
          .where('reporterId', isEqualTo: user.uid)
          .where('targetType', isEqualTo: 'comment')
          .get();

      if (mounted) {
        setState(() {
          for (var report in commentReports.docs) {
            final targetId = report.data()['targetId'] as String?;
            if (targetId != null) _reportedComments.add(targetId);
          }
        });
      }
    } catch (e) {
      print('❌ 신고 항목 불러오기 에러: $e');
    }
  }

  void _onScroll() {
    if (!_isNavigating && _scrollController.hasClients) {
      _savedScrollPosition = _scrollController.offset;
    }
  }

  void _onFocusChange() {
    if (_commentFocusNode.hasFocus) {
      _saveScrollPosition();
      final savedPos = _savedScrollPosition;
      // 키보드 올라온 후 스크롤 위치 복원 시도
      for (int i in [50, 150, 300, 500]) {
        Future.delayed(Duration(milliseconds: i), () {
          if (mounted && _scrollController.hasClients && savedPos > 0) {
            _scrollController.jumpTo(savedPos);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    NotificationState.setCurrentViewingVoteId(null);
    _voteDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _commentFocusNode.removeListener(_onFocusChange);
    _commentController.dispose();
    _commentFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveScrollPosition() {
    if (_scrollController.hasClients) {
      _savedScrollPosition = _scrollController.offset;
    }
  }

  void _restoreScrollToPosition(double position) {
    if (position <= 0) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(position);
    }
    for (int i = 0; i < 10; i++) {
      Future.delayed(Duration(milliseconds: i * 16), () {
        if (mounted &&
            _scrollController.hasClients &&
            _scrollController.offset != position) {
          _scrollController.jumpTo(position);
        }
      });
    }
  }

  Future<void> _loadUserVote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final voteDoc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('votes')
          .doc(widget.topicId)
          .get();
      if (voteDoc.exists && mounted) {
        setState(() {
          _selectedOptionIndex = voteDoc.data()?['optionIndex'] as int?;
          _confirmedOptionIndex = _selectedOptionIndex;
        });
      }
    } catch (_) {}
  }

  void _castVote(int index) {
    if (_selectedOptionIndex == index) return;
    if (_voteDebounceTimer != null) {
      _voteDebounceTimer?.cancel();
      _optimisticTargets.clear();
    }

    final previousIndex = _selectedOptionIndex;
    final Map<int, int> newTargets = {};

    if (previousIndex != null &&
        previousIndex >= 0 &&
        previousIndex < _currentServerCounts.length) {
      newTargets[previousIndex] = (_currentServerCounts[previousIndex] - 1)
          .clamp(0, double.infinity)
          .toInt();
    }
    if (index >= 0 && index < _currentServerCounts.length) {
      newTargets[index] = _currentServerCounts[index] + 1;
    }

    setState(() {
      _selectedOptionIndex = index;
      _optimisticTargets = newTargets;
    });

    _saveScrollPosition();
    final savedPos = _savedScrollPosition;
    _restoreScrollToPosition(savedPos);

    _voteDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performVote(index, previousIndex);
    });
  }

  Future<void> _performVote(int index, int? previousIndex) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _selectedOptionIndex = previousIndex);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      }
      return;
    }

    int? serverPreviousIndex = previousIndex;
    try {
      final userVoteDoc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('votes')
          .doc(widget.topicId)
          .get();
      if (userVoteDoc.exists) {
        serverPreviousIndex = userVoteDoc.data()?['optionIndex'] as int?;
      }
    } catch (_) {}

    final docRef = _db.collection('topics').doc(widget.topicId);
    try {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception('주제를 찾을 수 없습니다.');

        List<dynamic> counts = List.from(snapshot.data()!['voteCounts'] ?? []);
        int totalVotes = counts.fold<int>(
          0,
          (sum, count) => sum + (count as int? ?? 0),
        );

        if (serverPreviousIndex != null &&
            serverPreviousIndex >= 0 &&
            serverPreviousIndex < counts.length) {
          int prev = counts[serverPreviousIndex] as int? ?? 0;
          if (prev > 0) {
            counts[serverPreviousIndex] = prev - 1;
            totalVotes--;
          }
        }

        if (index < counts.length) {
          counts[index] = (counts[index] as int? ?? 0) + 1;
          totalVotes++;
        } else {
          throw Exception('유효하지 않은 선택지입니다.');
        }

        transaction.update(docRef, {
          'voteCounts': counts,
          'totalVotes': totalVotes,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('votes')
          .doc(widget.topicId)
          .set({
            'topicId': widget.topicId,
            'optionIndex': index,
            'votedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        setState(() {
          _confirmedOptionIndex = index;
          _optimisticTargets.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedOptionIndex = previousIndex;
          _optimisticTargets.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('투표에 실패했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 주제 작성자 차단 기능
  Future<void> _blockTopicAuthor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }
    if (_topicAuthorId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사용자 차단'),
        content: const Text('이 사용자를 차단하시겠습니까?\n이 사용자의 모든 게시물과 댓글이 즉시 숨겨집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _blockService.blockUser(_topicAuthorId!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자를 차단했습니다. 게시물이 숨겨집니다.')),
          );
          Navigator.pop(context); // 차단했으므로 현재 화면 닫기
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('차단 실패: $e')));
        }
      }
    }
  }

  // --- 기존 알림 및 댓글 관련 함수들은 유지 ---
  Future<void> _createNotification({
    required String targetUserId,
    required String type,
    required String message,
    String? topicId,
    String? commentId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || targetUserId == currentUser.uid) return;
    try {
      final targetUserDoc = await _db
          .collection('users')
          .doc(targetUserId)
          .get();
      if (!targetUserDoc.exists) return;
      final targetData = targetUserDoc.data();

      // 사용자 알림 설정 확인
      bool shouldSendPush = false;
      switch (type) {
        case 'topic_comment':
          shouldSendPush = targetData?['notifyTopicComments'] as bool? ?? true;
          break;
        case 'comment_reply':
          shouldSendPush = targetData?['notifyCommentReplies'] as bool? ?? true;
          break;
        case 'comment_like':
          shouldSendPush = targetData?['notifyCommentLikes'] as bool? ?? false;
          break;
        default:
          shouldSendPush = true;
      }

      // ★ [핵심 추가] 알림 보낸 사람(senderId)을 저장해야 나중에 차단할 때 필터링 가능
      await _db
          .collection('users')
          .doc(targetUserId)
          .collection('notifications')
          .add({
            'type': type,
            'message': message,
            'topicId': topicId,
            'commentId': commentId,
            'senderId': currentUser.uid, // ★ 차단 필터링을 위해 필수
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });

      // FCM 푸시 알림 전송 (사용자 설정이 켜져있고 FCM 토큰이 있는 경우)
      if (shouldSendPush) {
        final fcmToken = targetData?['fcmToken'] as String?;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          final title = _getNotificationTitle(type);
          await _db.collection('push_notifications').add({
            'fcmToken': fcmToken,
            'title': title,
            'body': message,
            'data': {
              'type': type,
              'topicId': topicId ?? '',
              'commentId': commentId ?? '',
            },
            'sent': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('❌ 알림 생성 에러: $e');
    }
  }

  String _getNotificationTitle(String type) {
    switch (type) {
      case 'topic_comment':
        return '새로운 댓글';
      case 'comment_reply':
        return '새로운 답글';
      case 'comment_like':
        return '공감 알림';
      default:
        return '알림';
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.isEmpty) return;
    if (ProfanityFilter.hasProfanity(_commentController.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('비속어가 포함되어 있습니다.')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("로그인이 필요합니다.")));
      return;
    }

    // 사용자 정보 가져오기
    String myNickname = '익명 유저';
    bool isPublic = true;
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        myNickname = userDoc.data()?['nickname'] ?? '익명 유저';
        isPublic = userDoc.data()?['isPublic'] ?? true;
      }
    } catch (_) {}

    // 뱃지 설정 - 투표한 선택지 반영
    String badgeText = '관전';
    int badgeColorValue = Colors.grey.value;
    
    try {
      // 현재 주제 정보 가져오기
      final topicDoc = await _db.collection('topics').doc(widget.topicId).get();
      if (topicDoc.exists) {
        final topicData = topicDoc.data();
        final options = List<String>.from(topicData?['options'] ?? []);
        
        // 투표한 선택지 확인 (확인된 투표 인덱스 우선, 없으면 선택된 인덱스)
        final votedOptionIndex = _confirmedOptionIndex ?? _selectedOptionIndex;
        
        if (votedOptionIndex != null && 
            votedOptionIndex >= 0 && 
            votedOptionIndex < options.length) {
          // 투표한 선택지가 있으면 해당 선택지를 배지로 설정
          badgeText = options[votedOptionIndex];
          
          // 선택지에 해당하는 색상 설정
          if (votedOptionIndex < _optionColors.length) {
            badgeColorValue = _optionColors[votedOptionIndex].value;
          }
        }
      }
    } catch (e) {
      print('⚠️ 배지 설정 중 오류: $e');
      // 오류 발생 시 기본값 유지
    }

    final newComment = {
      'uid': user.uid,
      'author': myNickname,
      'isPublic': isPublic,
      'content': _commentController.text,
      'badge': badgeText,
      'badgeColor': badgeColorValue,
      'time': Timestamp.now(),
      'likes': 0,
      'likedBy': [],
      'replies': [],
    };

    _saveScrollPosition();
    final savedPos = _savedScrollPosition;

    try {
      if (_replyingToDocId != null) {
        final commentRef = _db
            .collection('topics')
            .doc(widget.topicId)
            .collection('comments')
            .doc(_replyingToDocId);
        final parentDoc = await commentRef.get();
        if (!parentDoc.exists)
          throw ParentCommentDeletedException('원댓글이 삭제되었습니다.');

        await commentRef.update({
          'replies': FieldValue.arrayUnion([newComment]),
        });

        final parentUid = parentDoc.data()?['uid'];
        if (parentUid != null)
          _createNotification(
            targetUserId: parentUid,
            type: 'comment_reply',
            message: '$myNickname님이 답글을 남겼습니다.',
            topicId: widget.topicId,
            commentId: _replyingToDocId,
          );

        setState(() => _replyingToDocId = null);
      } else {
        final docRef = await _db
            .collection('topics')
            .doc(widget.topicId)
            .collection('comments')
            .add(newComment);

        // 주제 작성자에게 알림
        if (_topicAuthorId != null)
          _createNotification(
            targetUserId: _topicAuthorId!,
            type: 'topic_comment',
            message: '$myNickname님이 댓글을 남겼습니다.',
            topicId: widget.topicId,
            commentId: docRef.id,
          );
      }

      _commentController.clear();
      FocusScope.of(context).unfocus();
      _restoreScrollToPosition(savedPos);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('실패: $e')));
      _restoreScrollToPosition(savedPos);
    }
  }

  void _startReply(String docId, String authorName) {
    _saveScrollPosition();
    final savedPos = _savedScrollPosition;
    setState(() => _replyingToDocId = docId);
    _restoreScrollToPosition(savedPos);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).requestFocus(_commentFocusNode);
    });
  }

  void _cancelReply() {
    _saveScrollPosition();
    final savedPos = _savedScrollPosition;
    setState(() => _replyingToDocId = null);
    FocusScope.of(context).unfocus();
    _restoreScrollToPosition(savedPos);
  }

  Future<void> _deleteComment(String commentId, String? topicId) async {
    // ... 기존 삭제 로직 유지 ...
    if (topicId == null) return;
    _saveScrollPosition();
    final savedPos = _savedScrollPosition;
    try {
      await _db
          .collection('topics')
          .doc(topicId)
          .collection('comments')
          .doc(commentId)
          .delete();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
      _restoreScrollToPosition(savedPos);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제 실패')));
      _restoreScrollToPosition(savedPos);
    }
  }

  Future<void> _deleteReply(
    String commentId,
    String? topicId,
    int replyIndex,
  ) async {
    // ... 기존 답글 삭제 로직 유지 ...
    if (topicId == null) return;
    _saveScrollPosition();
    final savedPos = _savedScrollPosition;
    try {
      final docRef = _db
          .collection('topics')
          .doc(topicId)
          .collection('comments')
          .doc(commentId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;
        List replies = List.from(snap.data()!['replies'] ?? []);
        if (replyIndex >= 0 && replyIndex < replies.length) {
          replies.removeAt(replyIndex);
          tx.update(docRef, {'replies': replies});
        }
      });
      _restoreScrollToPosition(savedPos);
    } catch (_) {
      _restoreScrollToPosition(savedPos);
    }
  }

  Future<void> _toggleLike(
    Map<String, dynamic> item,
    String? commentId,
    String? topicId,
    int? replyIndex,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || topicId == null) return;

    _saveScrollPosition();
    final savedPos = _savedScrollPosition;

    try {
      if (replyIndex != null) {
        // 대댓글 공감 처리
        if (commentId == null) return;

        final commentRef = _db
            .collection('topics')
            .doc(topicId)
            .collection('comments')
            .doc(commentId);

        await _db.runTransaction((transaction) async {
          final commentSnap = await transaction.get(commentRef);
          if (!commentSnap.exists) return;

          final data = commentSnap.data() as Map<String, dynamic>;
          final replies = List<Map<String, dynamic>>.from(
              (data['replies'] as List<dynamic>?) ?? []);

          if (replyIndex >= 0 && replyIndex < replies.length) {
            final reply = replies[replyIndex];
            final likedBy = List<String>.from(reply['likedBy'] ?? []);
            final currentLikes = reply['likes'] as int? ?? 0;

            if (likedBy.contains(user.uid)) {
              // 공감 취소
              likedBy.remove(user.uid);
              replies[replyIndex] = {
                ...reply,
                'likedBy': likedBy,
                'likes': currentLikes - 1,
              };
            } else {
              // 공감 추가
              likedBy.add(user.uid);
              replies[replyIndex] = {
                ...reply,
                'likedBy': likedBy,
                'likes': currentLikes + 1,
              };

              // 대댓글 작성자에게 알림 (자신의 댓글이 아닌 경우)
              final replyAuthorId = reply['uid'] as String?;
              if (replyAuthorId != null &&
                  replyAuthorId != user.uid &&
                  _topicAuthorId != null) {
                _createNotification(
                  targetUserId: replyAuthorId,
                  type: 'comment_like',
                  message: '${FirebaseAuth.instance.currentUser?.displayName ?? "누군가"}님이 공감했습니다.',
                  topicId: topicId,
                  commentId: commentId,
                );
              }
            }

            transaction.update(commentRef, {'replies': replies});
          }
        });
      } else {
        // 일반 댓글 공감 처리
        if (commentId == null) return;

        final commentRef = _db
            .collection('topics')
            .doc(topicId)
            .collection('comments')
            .doc(commentId);

        await _db.runTransaction((transaction) async {
          final commentSnap = await transaction.get(commentRef);
          if (!commentSnap.exists) return;

          final data = commentSnap.data() as Map<String, dynamic>;
          final likedBy = List<String>.from(data['likedBy'] ?? []);
          final currentLikes = data['likes'] as int? ?? 0;

          if (likedBy.contains(user.uid)) {
            // 공감 취소
            likedBy.remove(user.uid);
            transaction.update(commentRef, {
              'likedBy': likedBy,
              'likes': currentLikes - 1,
            });
          } else {
            // 공감 추가
            likedBy.add(user.uid);
            transaction.update(commentRef, {
              'likedBy': likedBy,
              'likes': currentLikes + 1,
            });

            // 댓글 작성자에게 알림 (자신의 댓글이 아닌 경우)
            final commentAuthorId = data['uid'] as String?;
            if (commentAuthorId != null &&
                commentAuthorId != user.uid &&
                _topicAuthorId != null) {
              _createNotification(
                targetUserId: commentAuthorId,
                type: 'comment_like',
                message: '${FirebaseAuth.instance.currentUser?.displayName ?? "누군가"}님이 공감했습니다.',
                topicId: topicId,
                commentId: commentId,
              );
            }
          }
        });
      }

      _restoreScrollToPosition(savedPos);
    } catch (e) {
      print('❌ 공감 토글 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공감 처리 중 오류가 발생했습니다: $e')),
        );
      }
      _restoreScrollToPosition(savedPos);
    }
  }

  Future<void> _shareTopic() async {
    try {
      // 주제 데이터 가져오기
      final topicDoc = await _db.collection('topics').doc(widget.topicId).get();
      if (!topicDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주제를 찾을 수 없습니다.')),
        );
        return;
      }

      final data = topicDoc.data();
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주제 데이터를 불러올 수 없습니다.')),
        );
        return;
      }

      final title = data['title'] as String? ?? '제목 없음';
      final options = List<String>.from(data['options'] ?? []);

      // 공유 텍스트 포맷팅
      final StringBuffer shareText = StringBuffer();
      shareText.writeln(title);
      
      for (int i = 0; i < options.length; i++) {
        shareText.writeln('${i + 1}. ${options[i]}');
      }

      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        shareText.toString(),
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      print('❌ 공유 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _reportTopic() async {
    // ... 기존 신고 로직 유지 ...
    final reason = await ReportDialog.show(context);
    if (reason == null) return;
    try {
      await _reportService.report(
        targetId: widget.topicId,
        targetType: 'topic',
        reason: reason,
      );
      if (mounted) setState(() => _isTopicReported = true);
    } catch (_) {}
  }

  Future<void> _reportComment(String commentId) async {
    // ... 기존 댓글 신고 로직 유지 ...
    final reason = await ReportDialog.show(context);
    if (reason == null) return;
    try {
      await _reportService.report(
        targetId: commentId,
        targetType: 'comment',
        reason: reason,
        topicId: widget.topicId,
      );
      if (mounted) setState(() => _reportedComments.add(commentId));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardBgColor = isDark ? const Color(0xFF2D2D3A) : Colors.white;
    final inputFillColor = isDark ? const Color(0xFF1E1E2C) : Colors.grey[100];
    final borderColor = isDark ? Colors.white12 : Colors.grey[300]!;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('주제 상세', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _shareTopic),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'report') _reportTopic();
              if (value == 'block') _blockTopicAuthor();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 20, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('이 주제 신고하기', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // 자신이 쓴 글이 아니고, 작성자 ID를 알고 있을 때만 차단 메뉴 표시
              if (_topicAuthorId != null && _topicAuthorId != currentUser?.uid)
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      const Icon(Icons.block, size: 20, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('이 사용자 차단하기', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,

      // ★ 1. 화면 전체를 차단 목록 스트림으로 감싸기 (실시간 차단 반영)
      body: StreamBuilder<List<String>>(
        stream: _blockService.blockedUsersStream,
        initialData: _blockService.currentBlockedUsers,
        builder: (context, blockedSnapshot) {
          final blockedUserIds = blockedSnapshot.data ?? [];

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey('vote_screen_scroll'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ 2. 주제(투표) 스트림
                      StreamBuilder<DocumentSnapshot>(
                        stream: _topicStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Center(child: Text("오류가 발생했습니다."));
                          }
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return const Center(child: Text("삭제된 게시물입니다."));
                          }

                          final data =
                              snapshot.data!.data() as Map<String, dynamic>;

                          // 삭제된 상태 체크
                          if (data['status'] == 'deleted') {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) Navigator.pop(context);
                            });
                            return const SizedBox.shrink();
                          }

                          // ★ 차단된 사용자의 글인지 확인 (즉시 숨김 처리)
                          final authorId = data['authorId'] ?? data['uid'];
                          if (blockedUserIds.contains(authorId)) {
                            return Center(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.block,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "차단된 사용자의 게시물입니다.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("돌아가기"),
                                  ),
                                ],
                              ),
                            );
                          }

                          // 신고된 주제 처리
                          if (_isTopicReported) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: Text(
                                  '신고된 게시물입니다',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          // --- 투표 UI 그리기 ---
                          final List<String> options = List<String>.from(
                            data['options'] ?? [],
                          );
                          final List<String?> optionImages =
                              (data['optionImages'] as List?)
                                  ?.map((e) => e as String?)
                                  .toList() ??
                              List.filled(options.length, null);

                          _currentServerCounts = List<int>.from(
                            (data['voteCounts'] as List?)?.map(
                                  (e) => e as int? ?? 0,
                                ) ??
                                [],
                          );
                          List<int> displayCounts = List.from(
                            _currentServerCounts,
                          );

                          for (int i = 0; i < displayCounts.length; i++) {
                            if (_optimisticTargets.containsKey(i)) {
                              final target = _optimisticTargets[i]!;
                              if ((target > displayCounts[i]) ||
                                  (target < displayCounts[i])) {
                                displayCounts[i] = target;
                              }
                            }
                          }

                          final int displayTotalVotes = displayCounts.fold(
                            0,
                            (sum, count) => sum + count,
                          );

                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: isDark
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  data['title'] ?? '제목 없음',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Column(
                                  children: List.generate(options.length, (
                                    index,
                                  ) {
                                    final count = index < displayCounts.length
                                        ? displayCounts[index]
                                        : 0;
                                    final percent = displayTotalVotes == 0
                                        ? "0%"
                                        : "${((count / displayTotalVotes) * 100).toStringAsFixed(1)}%";
                                    final color =
                                        _optionColors[index %
                                            _optionColors.length];

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12.0,
                                      ),
                                      child: _buildVoteOption(
                                        index,
                                        options[index],
                                        percent,
                                        '($count표)',
                                        color,
                                        isDark,
                                        _selectedOptionIndex != null,
                                        imageUrl: index < optionImages.length
                                            ? optionImages[index]
                                            : null,
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '총 $displayTotalVotes표 참여',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // ★ 3. 댓글 스트림 (차단 필터링 적용)
                      StreamBuilder<QuerySnapshot>(
                        stream: _commentsStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Text("댓글 로딩 중...");

                          final docs = snapshot.data!.docs;

                          // (1) 내가 신고한 댓글 제외
                          final reportedFilteredDocs = docs
                              .where(
                                (doc) => !_reportedComments.contains(doc.id),
                              )
                              .toList();

                          // (2) 차단한 사용자의 댓글 제외 & Banned 상태 제외
                          final filteredDocs = reportedFilteredDocs.where((
                            doc,
                          ) {
                            final data = doc.data() as Map<String, dynamic>;
                            final authorId = data['uid'] as String?;
                            if (data['status'] == 'banned') return false;
                            // ★ 핵심: 차단 목록에 있는 작성자는 제외
                            return authorId != null &&
                                !blockedUserIds.contains(authorId);
                          }).toList();

                          // (3) 정렬
                          final sortedDocs = List<QueryDocumentSnapshot>.from(
                            filteredDocs,
                          );
                          if (_commentSort == '인기순') {
                            sortedDocs.sort((a, b) {
                              final aData = a.data() as Map<String, dynamic>;
                              final bData = b.data() as Map<String, dynamic>;
                              final likesDiff = (bData['likes'] as int? ?? 0)
                                  .compareTo(aData['likes'] as int? ?? 0);
                              if (likesDiff != 0) return likesDiff;
                              return (bData['time'] as Timestamp).compareTo(
                                aData['time'] as Timestamp,
                              );
                            });
                          } else {
                            sortedDocs.sort((a, b) {
                              final aTime =
                                  (a.data() as Map<String, dynamic>)['time']
                                      as Timestamp?;
                              final bTime =
                                  (b.data() as Map<String, dynamic>)['time']
                                      as Timestamp?;
                              if (aTime == null) return 1;
                              if (bTime == null) return -1;
                              return bTime.compareTo(aTime);
                            });
                          }

                          // 댓글 수 계산 (차단된 사람의 댓글은 카운트에서 제외됨)
                          int totalCommentCount = 0;
                          for (var doc in sortedDocs) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (data['isDeleted'] != true) totalCommentCount++;
                            // 답글 카운트 (차단된 답글 제외)
                            final replies = data['replies'] as List? ?? [];
                            for (var r in replies) {
                              if (r['isDeleted'] != true &&
                                  !blockedUserIds.contains(r['uid']))
                                totalCommentCount++;
                            }
                          }

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.local_fire_department,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '댓글 $totalCommentCount개',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      _saveScrollPosition();
                                      final saved = _savedScrollPosition;
                                      setState(
                                        () =>
                                            _commentSort = _commentSort == '최신순'
                                            ? '인기순'
                                            : '최신순',
                                      );
                                      _restoreScrollToPosition(saved);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _commentSort == '최신순'
                                                ? Icons.access_time
                                                : Icons.favorite,
                                            size: 16,
                                            color: textColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _commentSort,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: sortedDocs.length,
                                itemBuilder: (context, index) {
                                  final doc = sortedDocs[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  // ★ 답글 필터링: 차단된 사용자의 답글은 숨김
                                  List<dynamic> allReplies =
                                      data['replies'] ?? [];
                                  final visibleReplies = allReplies.where((
                                    reply,
                                  ) {
                                    final rData = reply as Map<String, dynamic>;
                                    return !blockedUserIds.contains(
                                      rData['uid'],
                                    );
                                  }).toList();

                                  return Column(
                                    children: [
                                      _buildCommentItem(
                                        item: data,
                                        textColor: textColor,
                                        badgeColorOverride: Color(
                                          data['badgeColor'] ??
                                              Colors.grey.value,
                                        ),
                                        isDark: isDark,
                                        commentId: doc.id,
                                        topicId: widget.topicId,
                                        onReplyTap: () =>
                                            _startReply(doc.id, data['author']),
                                        onDelete: () => _deleteComment(
                                          doc.id,
                                          widget.topicId,
                                        ),
                                        onReport:
                                            data['uid'] != currentUser?.uid
                                            ? () => _reportComment(doc.id)
                                            : null,
                                      ),
                                      if (visibleReplies.isNotEmpty)
                                        ...visibleReplies.map((reply) {
                                          final rData =
                                              reply as Map<String, dynamic>;
                                          final originalIndex = allReplies
                                              .indexOf(reply);
                                          final isMyReply =
                                              rData['uid'] == currentUser?.uid;
                                          final isDeleted =
                                              rData['isDeleted'] == true;

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 32.0,
                                            ),
                                            child: _buildCommentItem(
                                              item: rData,
                                              textColor: textColor,
                                              badgeColorOverride: Color(
                                                rData['badgeColor'] ??
                                                    Colors.grey.value,
                                              ),
                                              isDark: isDark,
                                              isReply: true,
                                              commentId: doc.id,
                                              topicId: widget.topicId,
                                              replyIndex: originalIndex,
                                              onDelete:
                                                  (isMyReply && !isDeleted)
                                                  ? () => _deleteReply(
                                                      doc.id,
                                                      widget.topicId,
                                                      originalIndex,
                                                    )
                                                  : null,
                                              onReport:
                                                  (!isMyReply && !isDeleted)
                                                  ? () => _reportComment(doc.id)
                                                  : null,
                                            ),
                                          );
                                        }),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_replyingToDocId != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  child: Row(
                    children: [
                      const Icon(
                        Icons.subdirectory_arrow_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "답글 작성 중...",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _cancelReply,
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: _replyingToDocId != null
                              ? '답글을 입력하세요...'
                              : '의견을 남기세요...',
                          filled: true,
                          fillColor: inputFillColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onTap: _saveScrollPosition,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _addComment,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE91E63),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UI 위젯들 ---
  Widget _buildVoteOption(
    int index,
    String label,
    String percent,
    String count,
    Color color,
    bool isDark,
    bool hasVoted, {
    String? imageUrl,
  }) {
    final isSelected = _selectedOptionIndex == index;
    return GestureDetector(
      onTap: () => _castVote(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color
                : (hasVoted
                      ? Colors.transparent
                      : (isDark ? Colors.white24 : Colors.grey[300]!)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? color : Colors.grey[400],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasVoted) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        percent,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isSelected
                              ? color
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      Text(
                        count,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem({
    required Map<String, dynamic> item,
    required Color textColor,
    Color? badgeColorOverride,
    required bool isDark,
    bool isReply = false,
    String? commentId,
    String? topicId,
    int? replyIndex,
    VoidCallback? onReplyTap,
    VoidCallback? onDelete,
    VoidCallback? onReport,
  }) {
    return _CommentItemWidget(
      key: ValueKey('${commentId}_${replyIndex ?? 'main'}'),
      item: item,
      textColor: textColor,
      badgeColorOverride: badgeColorOverride,
      isDark: isDark,
      isReply: isReply,
      commentId: commentId,
      topicId: topicId,
      replyIndex: replyIndex,
      onReplyTap: onReplyTap,
      onDelete: onDelete,
      onReport: onReport,
      scrollController: _scrollController,
      onToggleLike: (item, cid, tid, rid) => _toggleLike(item, cid, tid, rid),
    );
  }
}

// 댓글 아이템 위젯 (AutomaticKeepAliveClientMixin 적용)
class _CommentItemWidget extends StatefulWidget {
  final Map<String, dynamic> item;
  final Color textColor;
  final Color? badgeColorOverride;
  final bool isDark;
  final bool isReply;
  final String? commentId;
  final String? topicId;
  final int? replyIndex;
  final VoidCallback? onReplyTap;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final ScrollController scrollController;
  final Function(Map<String, dynamic>, String?, String?, int?) onToggleLike;

  const _CommentItemWidget({
    super.key,
    required this.item,
    required this.textColor,
    this.badgeColorOverride,
    required this.isDark,
    this.isReply = false,
    this.commentId,
    this.topicId,
    this.replyIndex,
    this.onReplyTap,
    this.onDelete,
    this.onReport,
    required this.scrollController,
    required this.onToggleLike,
  });

  @override
  State<_CommentItemWidget> createState() => _CommentItemWidgetState();
}

class _CommentItemWidgetState extends State<_CommentItemWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDeleted = widget.item['isDeleted'] == true;
    final displayAuthor = isDeleted
        ? '(알 수 없음)'
        : (widget.item['author'] ?? '익명 유저');
    final displayContent = isDeleted
        ? '삭제된 댓글입니다'
        : (widget.item['content'] ?? '');
    final contentColor = isDeleted ? Colors.grey[600]! : widget.textColor;
    String timeStr = '방금 전';
    if (widget.item['time'] is Timestamp) {
      DateTime d = (widget.item['time'] as Timestamp).toDate();
      timeStr = "${d.month}/${d.day} ${d.hour}:${d.minute}";
    }

    // 프로필 이동 함수
    void _navigateToProfile() {
      if (isDeleted) return;
      final authorId = widget.item['uid'] as String?;
      if (authorId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(
              userId: authorId,
              userName: displayAuthor,
            ),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 아이콘 (클릭 가능하도록 확대된 영역)
          GestureDetector(
            onTap: _navigateToProfile,
            child: Padding(
              padding: const EdgeInsets.all(4.0), // 클릭 영역 확대
              child: CircleAvatar(
                backgroundColor: Colors.grey[800],
                radius: widget.isReply ? 12 : 18,
                child: Text(
                  isDeleted ? '?' : (widget.item['author']?[0] ?? '?'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.isReply ? 10 : 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _navigateToProfile,
                      child: Text(
                        displayAuthor,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDeleted
                              ? Colors.grey[600]!
                              : const Color(0xFFBB86FC),
                          fontSize: widget.isReply ? 13 : 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.badgeColorOverride ?? Colors.grey,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.item['badge'],
                        style: TextStyle(
                          color: widget.badgeColorOverride ?? Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  displayContent,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: contentColor,
                    fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (!isDeleted) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (!widget.isReply)
                        GestureDetector(
                          onTap: widget.onReplyTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4.0,
                              horizontal: 8.0,
                            ),
                            child: Text(
                              '답글',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (!widget.isReply) const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          if (widget.topicId != null)
                            widget.onToggleLike(
                              widget.item,
                              widget.commentId,
                              widget.topicId,
                              widget.replyIndex,
                            );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4.0,
                            horizontal: 8.0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.item['likedBy']?.contains(
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid,
                                        ) ==
                                        true
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color:
                                    widget.item['likedBy']?.contains(
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid,
                                        ) ==
                                        true
                                    ? Colors.red
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${widget.item['likes'] ?? 0}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.item['uid'] !=
                              FirebaseAuth.instance.currentUser?.uid &&
                          widget.onReport != null) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onReport,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4.0,
                              horizontal: 8.0,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.flag_outlined,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '신고',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.item['uid'] ==
                              FirebaseAuth.instance.currentUser?.uid &&
                          widget.onDelete != null) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: widget.onDelete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4.0,
                              horizontal: 8.0,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '삭제',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
