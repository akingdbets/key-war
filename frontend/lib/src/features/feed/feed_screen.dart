import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_drawer.dart';
import '../vote/vote_screen.dart';
import '../profile/notification_history_screen.dart';
import 'create_topic_screen.dart';
import '../report/report_service.dart';
import '../report/report_dialog.dart';
import '../block/block_service.dart'; // BlockService import 필수
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin {
  String _selectedCategory = '전체';
  String _selectedSort = '최신순';
  String _selectedPeriod = '전체';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Firebase 및 서비스 인스턴스
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ReportService _reportService = ReportService();

  // ★ BlockService는 싱글톤 인스턴스 사용
  final BlockService _blockService = BlockService.instance;

  // 신고된 주제 추적 (로컬 상태)
  final Set<String> _reportedTopics = {};

  // 스크롤 컨트롤러
  late final ScrollController _scrollController;

  // Stream 캐싱
  Stream<QuerySnapshot>? _topicsStream;

  // 뒤로가기 버튼 상태
  DateTime? _lastPressedAt;

  // 카테고리 리스트
  final List<String> _categories = [
    '전체',
    '음식',
    '게임',
    '연애',
    '스포츠',
    '유머',
    '정치',
    '직장인',
    '패션',
    '기타',
  ];

  final List<String> _periods = ['전체', '1일', '1주', '1달', '직접설정'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadReportedTopics();

    // 앱 시작 시 차단 목록 최신화 확인
    _blockService.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUserBanStatus();
    });
  }

  Future<void> _checkUserBanStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final authService = AuthService();
      final isAllowed = await authService.checkUserStatus(user.uid);

      if (!isAllowed && mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('계정이 정지되어 로그아웃되었습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ 유저 제재 상태 체크 에러: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadReportedTopics() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final reports = await _db
          .collection('reports')
          .where('reporterId', isEqualTo: user.uid)
          .where('targetType', isEqualTo: 'topic')
          .get();

      if (mounted) {
        setState(() {
          for (var report in reports.docs) {
            final targetId = report.data()['targetId'] as String?;
            if (targetId != null) {
              _reportedTopics.add(targetId);
            }
          }
        });
      }
    } catch (e) {
      print('❌ 신고한 주제 목록 불러오기 에러: $e');
    }
  }

  // Firestore 쿼리 (인덱스 문제 방지를 위해 단순화)
  Query<Map<String, dynamic>> _getTopicsQuery() {
    return _db.collection('topics');
  }

  Stream<QuerySnapshot> _getTopicsStream() {
    _topicsStream ??= _getTopicsQuery().snapshots();
    return _topicsStream!;
  }

  DateTime? _getPeriodStartDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case '1일':
        return now.subtract(const Duration(days: 1));
      case '1주':
        return now.subtract(const Duration(days: 7));
      case '1달':
        return now.subtract(const Duration(days: 30));
      case '직접설정':
        return _customStartDate;
      default:
        return null;
    }
  }

  // 데이터 필터링 및 정렬 로직
  List<QueryDocumentSnapshot> _filterAndSortDocuments(
    List<QueryDocumentSnapshot> docs,
    List<String> blockedUsers, // ★ 차단된 사용자 목록 전달받음
  ) {
    // 1. 기본 필터링 (상태, 차단유저, 신고글)
    List<QueryDocumentSnapshot> filteredDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final status = data?['status'] as String?;
      final authorId =
          data?['authorId'] as String?; // authorId 필드명 확인 (uid 일수도 있음)

      // 삭제되거나 밴 된 게시물 제외
      if (status == 'deleted' || status == 'banned') return false;

      // ★ 차단된 사용자의 글 제외
      if (authorId != null && blockedUsers.contains(authorId)) return false;

      // 내가 신고한 글 제외
      if (_reportedTopics.contains(doc.id)) return false;

      return true;
    }).toList();

    // 2. 카테고리 필터링
    if (_selectedCategory != '전체') {
      filteredDocs = filteredDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data?['category'] == _selectedCategory;
      }).toList();
    }

    // 3. 조회기간 필터링
    final periodStart = _getPeriodStartDate();
    if (periodStart != null || _customEndDate != null) {
      filteredDocs = filteredDocs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        final createdAt = data?['createdAt'] as Timestamp?;
        if (createdAt == null) return false;

        final docDate = createdAt.toDate();
        final startDate = _customStartDate ?? periodStart;
        final endDate = _customEndDate ?? DateTime.now();

        return docDate.isAfter(startDate!) &&
            docDate.isBefore(endDate.add(const Duration(days: 1)));
      }).toList();
    }

    // 4. 정렬
    final sortedDocs = List<QueryDocumentSnapshot>.from(filteredDocs);
    if (_selectedSort == '인기순') {
      sortedDocs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>?;
        final bData = b.data() as Map<String, dynamic>?;
        final aVotes = aData?['totalVotes'] as int? ?? 0;
        final bVotes = bData?['totalVotes'] as int? ?? 0;
        return bVotes.compareTo(aVotes);
      });
    } else {
      sortedDocs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>?;
        final bData = b.data() as Map<String, dynamic>?;
        final aTime = aData?['createdAt'] as Timestamp?;
        final bTime = bData?['createdAt'] as Timestamp?;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    }

    return sortedDocs;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          setState(() {
            _lastPressedAt = now;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '뒤로 버튼을 한번 더 누르면 종료됩니다.',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: isDark
                    ? const Color(0xFF2D2D3A)
                    : Colors.grey[800],
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
              ),
            );
          }
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        drawer: const MainDrawer(),
        floatingActionButton: _buildFloatingActionButton(isDark),
        body: CustomScrollView(
          key: const PageStorageKey<String>('feed_scroll_position'),
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(),
            _buildFilterSection(context),

            // ★ [핵심] 차단 목록 스트림을 가장 바깥에서 구독
            StreamBuilder<List<String>>(
              stream: _blockService.blockedUsersStream,
              initialData: _blockService.currentBlockedUsers,
              builder: (context, blockedSnapshot) {
                // 차단된 사용자 목록 (데이터가 없으면 빈 리스트)
                final blockedUsers = blockedSnapshot.data ?? [];

                // 그 다음 Firestore 데이터 구독
                return StreamBuilder<QuerySnapshot>(
                  stream: _getTopicsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return _buildErrorView(snapshot.error.toString());
                    }

                    // 필터링 시 차단 목록(blockedUsers)을 함께 전달
                    final docs = _filterAndSortDocuments(
                      snapshot.data!.docs,
                      blockedUsers,
                    );
                    final topicCount = docs.length;

                    if (topicCount == 0) {
                      return _buildEmptyView(isDark);
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                child: Text(
                                  '총 $topicCount개의 주제',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: _buildTopicItem(docs[index]),
                              ),
                            ],
                          );
                        }
                        return Container(
                          margin: EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            top: 10.0,
                            bottom: index == docs.length - 1 ? 100.0 : 10.0,
                          ),
                          child: _buildTopicItem(docs[index]),
                        );
                      }, childCount: docs.length),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Components ---

  Widget _buildFloatingActionButton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D3A) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFF512F), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF512F).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CreateTopicScreen()),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF512F)),
        label: const Text(
          '새 주제',
          style: TextStyle(
            color: Color(0xFFFF512F),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      title: const Text(
        'Key War',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationHistoryScreen(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) =>
                  _buildCategoryChip(context, _categories[index]),
            ),
          ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  '조회기간: ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _periods.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) =>
                        _buildPeriodChip(context, _periods[index]),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildSortButton(context, '최신순'),
                const SizedBox(width: 10),
                _buildSortButton(context, '인기순'),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(child: Text("오류가 발생했습니다: $error")),
      ),
    );
  }

  Widget _buildEmptyView(bool isDark) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: const Color(0xFFFF512F).withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedCategory == '전체'
                  ? '아직 주제가 없습니다'
                  : '$_selectedCategory 카테고리에 주제가 없습니다',
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '새로운 주제를 만들어보세요!',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // authorId가 없으면 빈 문자열 처리
    final authorId = data['authorId'] ?? data['uid'] ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('topics')
          .doc(doc.id)
          .collection('comments')
          .snapshots(),
      builder: (context, commentsSnapshot) {
        String hotComment = '가장 먼저 댓글을 달아보세요 !';
        if (commentsSnapshot.hasData &&
            commentsSnapshot.data!.docs.isNotEmpty) {
          QueryDocumentSnapshot? bestComment;
          int maxLikes = -1;
          for (var commentDoc in commentsSnapshot.data!.docs) {
            final commentData = commentDoc.data() as Map<String, dynamic>;
            final likes = commentData['likes'] as int? ?? 0;
            if (likes > maxLikes) {
              maxLikes = likes;
              bestComment = commentDoc;
            }
          }
          if (bestComment != null && maxLikes > 0) {
            final bestData = bestComment.data() as Map<String, dynamic>;
            hotComment = bestData['content'] as String? ?? '가장 먼저 댓글을 달아보세요 !';
          }
        }

        return ArenaCard(
          topicId: doc.id,
          topicAuthorId: authorId, // 작성자 ID 전달
          category: data['category'] ?? '기타',
          title: data['title'] ?? '제목 없음',
          initialVoteCounts: List<int>.from(data['voteCounts'] ?? []),
          options: List<String>.from(data['options'] ?? []),
          hotComment: hotComment,
          onReport: () => _reportTopic(doc.id),
        );
      },
    );
  }

  // --- Helper Methods ---

  Future<void> _reportTopic(String topicId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final reason = await ReportDialog.show(context);
    if (reason == null) return;

    try {
      await _reportService.report(
        targetId: topicId,
        targetType: 'topic',
        reason: reason,
      );
      if (mounted) {
        setState(() => _reportedTopics.add(topicId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신고 실패: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Widget _buildCategoryChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedCategory == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF512F).withOpacity(0.1)
              : (isDark ? Colors.transparent : Colors.white),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF512F)
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFFFF512F)
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedPeriod == label;
    return GestureDetector(
      onTap: () async {
        if (label == '직접설정') {
          final DateTimeRange? picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            initialDateRange: _customStartDate != null && _customEndDate != null
                ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
                : null,
          );
          if (picked != null) {
            setState(() {
              _selectedPeriod = '직접설정';
              _customStartDate = picked.start;
              _customEndDate = picked.end;
            });
          }
        } else {
          setState(() {
            _selectedPeriod = label;
            _customStartDate = null;
            _customEndDate = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF512F).withOpacity(0.1)
              : (isDark ? Colors.transparent : Colors.white),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF512F)
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFFFF512F)
                : (isDark ? Colors.grey[400] : Colors.grey[700]),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSortButton(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _selectedSort == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedSort = label),
      child: Text(
        label,
        style: TextStyle(
          color: isActive
              ? const Color(0xFFFF512F)
              : (isDark ? Colors.grey : Colors.black54),
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ArenaCard
// -----------------------------------------------------------------------------

class ArenaCard extends StatefulWidget {
  final String topicId;
  final String topicAuthorId; // 차단을 위해 필요
  final String category;
  final String title;
  final List<int> initialVoteCounts;
  final List<String> options;
  final String hotComment;
  final List<Color>? colors;
  final VoidCallback? onReport;

  const ArenaCard({
    super.key,
    required this.topicId,
    required this.topicAuthorId,
    required this.category,
    required this.title,
    required this.initialVoteCounts,
    required this.options,
    required this.hotComment,
    this.colors,
    this.onReport,
  });

  @override
  State<ArenaCard> createState() => _ArenaCardState();
}

class _ArenaCardState extends State<ArenaCard> {
  List<int> _voteCounts = [];
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _voteCounts = List.from(widget.initialVoteCounts);
  }

  @override
  void didUpdateWidget(ArenaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialVoteCounts != widget.initialVoteCounts) {
      setState(() {
        _voteCounts = List.from(widget.initialVoteCounts);
      });
    }
  }

  // 차단 기능 추가
  Future<void> _blockAuthor() async {
    if (widget.topicAuthorId.isEmpty) return;

    // 확인 다이얼로그
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
        await BlockService.instance.blockUser(widget.topicAuthorId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자를 차단했습니다. 게시물이 숨겨집니다.')),
          );
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

  Future<void> _castVote(int index) async {
    if (_isVoting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    _isVoting = true;
    int? previousIndex;

    try {
      final userVoteDoc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('votes')
          .doc(widget.topicId)
          .get();
      if (userVoteDoc.exists) {
        previousIndex = userVoteDoc.data()?['optionIndex'] as int?;
      }
    } catch (_) {}

    if (previousIndex == index) {
      _isVoting = false;
      return;
    }

    // 낙관적 UI 업데이트
    setState(() {
      if (previousIndex != null &&
          previousIndex >= 0 &&
          previousIndex < _voteCounts.length) {
        _voteCounts[previousIndex]--;
      }
      if (index >= 0 && index < _voteCounts.length) {
        _voteCounts[index]++;
      }
    });

    final docRef = _db.collection('topics').doc(widget.topicId);
    try {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception('Topic not found');

        List<dynamic> counts = List.from(snapshot.data()!['voteCounts'] ?? []);
        int totalVotes = counts.fold<int>(
          0,
          (sum, count) => sum + (count as int? ?? 0),
        );

        if (previousIndex != null &&
            previousIndex >= 0 &&
            previousIndex < counts.length) {
          int prev = counts[previousIndex] as int;
          if (prev > 0) {
            counts[previousIndex] = prev - 1;
            totalVotes--;
          }
        }
        if (index >= 0 && index < counts.length) {
          counts[index] = (counts[index] as int) + 1;
          totalVotes++;
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
    } catch (e) {
      // 롤백
      setState(() {
        if (previousIndex != null) _voteCounts[previousIndex]++;
        _voteCounts[index]--;
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('투표 실패')));
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  double _getPercentValue(int index, int total) =>
      total == 0 ? 0.0 : _voteCounts[index] / total;
  String _getPercentString(int index, int total) => total == 0
      ? '0%'
      : '${((_voteCounts[index] / total) * 100).toStringAsFixed(1)}%';

  static const List<Color> _defaultColors = [
    Colors.blueAccent,
    Colors.redAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
  ];

  List<Color> _getCategoryGradient(String category) {
    // ... 기존 그라데이션 코드 유지 ...
    final gradientMap = <String, List<Color>>{
      '음식': [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)],
      '게임': [const Color(0xFF6B8DD6), const Color(0xFF8E37D7)],
      '연애': [const Color(0xFFFF6B9D), const Color(0xFFC44569)],
      '스포츠': [const Color(0xFF4ECDC4), const Color(0xFF44A08D)],
      '유머': [const Color(0xFFFFD93D), const Color(0xFFFF6B6B)],
      '정치': [const Color(0xFF4A90E2), const Color(0xFF357ABD)],
      '직장인': [const Color(0xFF667EEA), const Color(0xFF764BA2)],
      '패션': [const Color(0xFFF093FB), const Color(0xFFF5576C)],
      '기타': [const Color(0xFF6B8DD6), const Color(0xFF8E37D7)],
    };
    return gradientMap[category] ??
        [const Color(0xFF6B8DD6), const Color(0xFF8E37D7)];
  }

  Color _getCategoryGlowColor(String category) {
    // ... 기존 색상 코드 유지 ...
    return Colors.blueAccent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int totalVotes = _voteCounts.fold(0, (a, b) => a + b);
    final colors = widget.colors ?? _defaultColors;
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? _db
                .collection('users')
                .doc(user.uid)
                .collection('votes')
                .doc(widget.topicId)
                .snapshots()
          : null,
      builder: (context, voteSnapshot) {
        int? currentSelectedIndex;
        if (voteSnapshot.hasData && voteSnapshot.data!.exists) {
          currentSelectedIndex =
              (voteSnapshot.data!.data()
                  as Map<String, dynamic>)['optionIndex'];
        }
        final bool hasVoted = currentSelectedIndex != null;

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VoteScreen(topicId: widget.topicId),
            ),
          ),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: isDark
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, const Color(0xFFF5F7FA)],
                    ),
              color: isDark ? const Color(0xFF2D2D3A) : null,
              borderRadius: BorderRadius.circular(20.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 카테고리 칩 + 더보기 메뉴(신고/차단)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _getCategoryGradient(widget.category),
                              ),
                        color: isDark ? Colors.white10 : null,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.category,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      onSelected: (value) {
                        if (value == 'report') widget.onReport?.call();
                        if (value == 'block') _blockAuthor();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                size: 18,
                                color: Colors.red,
                              ),
                              SizedBox(width: 10),
                              Text('이 주제 신고하기'),
                            ],
                          ),
                        ),
                        if (widget.topicAuthorId.isNotEmpty &&
                            widget.topicAuthorId != user?.uid)
                          const PopupMenuItem(
                            value: 'block',
                            child: Row(
                              children: [
                                Icon(Icons.block, size: 18, color: Colors.red),
                                SizedBox(width: 10),
                                Text('이 사용자 차단하기'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                // 투표 옵션들
                Column(
                  children: List.generate(widget.options.length, (index) {
                    final isSelected = currentSelectedIndex == index;
                    final color = colors[index % colors.length];
                    final percentValue = _getPercentValue(index, totalVotes);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: GestureDetector(
                        onTap: () => _castVote(index),
                        child: Stack(
                          children: [
                            Container(
                              height: 56,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.black26
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : Colors.transparent,
                                  width: isSelected ? 2.5 : 1,
                                ),
                              ),
                            ),
                            if (hasVoted)
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    height: 56,
                                    width: constraints.maxWidth * percentValue,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  );
                                },
                              ),
                            Container(
                              height: 56,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.options[index],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? color
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.grey[700]),
                                      ),
                                    ),
                                  ),
                                  if (hasVoted)
                                    Text(
                                      _getPercentString(index, totalVotes),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? color : Colors.grey,
                                      ),
                                    ),
                                  if (isSelected)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: color,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                // 하단 베댓 및 댓글보기 버튼
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '🔥 베댓: ',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.hotComment,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$totalVotes명 참여',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              VoteScreen(topicId: widget.topicId),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Text('댓글 보기', style: TextStyle(fontSize: 12)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios, size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
