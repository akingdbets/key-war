import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_setting_screen.dart';
import '../vote/vote_screen.dart';
import '../block/block_service.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // 사용자 ID (null이면 현재 로그인한 사용자)
  final String? userName; // 사용자 이름 (선택, 댓글에서 클릭한 경우)
  final bool? isPublic; // 공개 여부 (선택)

  const ProfileScreen({
    super.key, 
    this.userId,
    this.userName,
    this.isPublic,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _selectedIndex = 0;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final BlockService _blockService = BlockService();

  // 댓글 개수 가져오기 (collectionGroup 인덱스 문제 회피)
  Future<int> _getCommentCount(String userId) async {
    try {
      // 모든 주제를 가져와서 각 주제의 comments 서브컬렉션에서 사용자 댓글 찾기
      final topicsSnapshot = await _db.collection('topics').get();
      int totalComments = 0;
      
      for (var topicDoc in topicsSnapshot.docs) {
        final commentsSnapshot = await _db
            .collection('topics')
            .doc(topicDoc.id)
            .collection('comments')
            .where('uid', isEqualTo: userId)
            .get();
        totalComments += commentsSnapshot.docs.length;
      }
      
      return totalComments;
    } catch (e) {
      print("댓글 개수 계산 에러: $e");
      return 0;
    }
  }

  // 투표 개수 가져오기 (삭제된 주제의 투표 제외)
  Future<int> _getVoteCount(String userId) async {
    try {
      final votesSnapshot = await _db.collection('users').doc(userId).collection('votes').get();
      int validVoteCount = 0;
      
      // 각 투표의 주제가 존재하는지 확인
      for (var voteDoc in votesSnapshot.docs) {
        final topicId = voteDoc.id;
        final topicDoc = await _db.collection('topics').doc(topicId).get();
        
        // 주제가 존재하면 카운트에 포함
        if (topicDoc.exists) {
          validVoteCount++;
        }
      }
      
      return validVoteCount;
    } catch (e) {
      print("투표 개수 계산 에러: $e");
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId ?? currentUser?.uid;
    
    if (targetUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필', style: TextStyle(fontWeight: FontWeight.bold))),
        body: const Center(child: Text('로그인이 필요합니다.')),
      );
    }

    // 내 프로필인지 확인
    final bool isMe = targetUserId == currentUser?.uid;
    
    // 차단된 사용자인지 확인
    final bool isBlocked = !isMe && _blockService.isUserBlocked(targetUserId);
    
    print("🔍 프로필 화면 - targetUserId: $targetUserId, isMe: $isMe, isBlocked: $isBlocked");

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('users').doc(targetUserId).snapshots(),
          builder: (context, snapshot) {
            String userName = '익명 유저';
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              userName = data?['nickname'] ?? widget.userName ?? '익명 유저';
            } else {
              userName = widget.userName ?? '익명 유저';
            }
            return Text(
              isMe ? '내 활동' : '$userName님의 활동',
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isMe)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationSettingScreen()),
                ).then((_) => setState(() {}));
              },
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'block') {
                  _blockUser(targetUserId);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('이 사용자 차단하기'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: isBlocked
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '차단된 사용자입니다',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '이 사용자의 프로필을 볼 수 없습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(targetUserId).snapshots(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final userName = userData?['nickname'] ?? widget.userName ?? '익명 유저';
                final isPublic = userData?['isPublic'] as bool? ?? widget.isPublic ?? true;
                final canView = isMe || (isPublic == true);

          return Column(
            children: [
              const SizedBox(height: 20),
              // 프로필 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D2D3A) : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(color: Color(0xFFBB86FC), fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (!isPublic) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (!canView)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 60, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          '비공개 계정입니다.',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '활동 내역을 볼 수 없습니다.',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // 탭 버튼
                StreamBuilder<QuerySnapshot>(
                  stream: _db.collection('topics').where('authorId', isEqualTo: targetUserId).snapshots(),
                  builder: (context, topicsSnapshot) {
                    return FutureBuilder<int>(
                      future: _getVoteCount(targetUserId), // 삭제된 주제 제외한 투표 개수
                      builder: (context, voteCountSnapshot) {
                        return FutureBuilder<int>(
                          future: _getCommentCount(targetUserId),
                          builder: (context, commentSnapshot) {
                            final topicCount = topicsSnapshot.hasData ? topicsSnapshot.data!.docs.length : 0;
                            final commentCount = commentSnapshot.hasData ? commentSnapshot.data! : 0;
                            final voteCount = voteCountSnapshot.hasData ? voteCountSnapshot.data! : 0;
                            
                            // 디버깅 로그
                            if (topicsSnapshot.hasData) {
                              print("📊 주제 개수: $topicCount");
                            }
                            if (voteCountSnapshot.hasData) {
                              print("📊 투표 개수: $voteCount");
                            }
                            if (commentSnapshot.hasData) {
                              print("📊 댓글 개수: $commentCount");
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                children: [
                                  _buildTabButton('댓글', commentCount.toString(), 0, isDark),
                                  const SizedBox(width: 8),
                                  _buildTabButton('투표', voteCount.toString(), 1, isDark),
                                  const SizedBox(width: 8),
                                  _buildTabButton('주제', topicCount.toString(), 2, isDark),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 20),

                // 리스트 영역
                Expanded(
                  child: _buildContentList(targetUserId, isDark),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentList(String userId, bool isDark) {
    switch (_selectedIndex) {
      case 0:
        return _buildCommentsList(userId, isDark);
      case 1:
        return _buildVotesList(userId, isDark);
      case 2:
        return _buildTopicsList(userId, isDark);
      default:
        return const SizedBox();
    }
  }

  Widget _buildCommentsList(String userId, bool isDark) {
    // collectionGroup 인덱스 문제 회피: 모든 주제를 가져와서 클라이언트에서 필터링
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('topics').snapshots(),
      builder: (context, topicsSnapshot) {
        if (topicsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!topicsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // 모든 주제의 댓글을 가져와서 사용자 댓글만 필터링
        return FutureBuilder<List<QueryDocumentSnapshot>>(
          future: _getUserComments(userId, topicsSnapshot.data!.docs),
          builder: (context, commentsSnapshot) {
            if (commentsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final docs = commentsSnapshot.data ?? [];

            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.comment_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('작성한 댓글이 없습니다', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              );
            }

            // 클라이언트에서 정렬 (time 기준)
            final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
            sortedDocs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>?;
              final bData = b.data() as Map<String, dynamic>?;
              final aTime = aData?['time'] as Timestamp?;
              final bTime = bData?['time'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime); // 내림차순
            });

            return ListView.builder(
              key: const PageStorageKey<String>('profile_comments'), // 스크롤 위치 유지
              padding: const EdgeInsets.all(16),
              itemCount: sortedDocs.length > 50 ? 50 : sortedDocs.length,
              itemBuilder: (context, index) {
                final doc = sortedDocs[index];
                final data = doc.data() as Map<String, dynamic>;
                
                // topicId 추출: doc.reference.parent.parent?.id 사용
                final topicId = doc.reference.parent.parent?.id ?? '';
                
                final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
                final isMyComment = data['uid'] == currentUserId;
                final isDeleted = data['isDeleted'] == true;
                
                return _buildActivityItem(
                  topicTitle: '주제 보기',
                  badge: data['badge'] ?? '관전',
                  content: data['content'] ?? '',
                  date: _formatDate(data['time'] as Timestamp?),
                  isDark: isDark,
                  onTap: () {
                    if (topicId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => VoteScreen(topicId: topicId)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('주제를 찾을 수 없습니다.')),
                      );
                    }
                  },
                  onDelete: (isMyComment && !isDeleted) ? () => _deleteComment(context, topicId, doc.id, isDark) : null,
                );
              },
            );
          },
        );
      },
    );
  }

  // 사용자 댓글 가져오기
  Future<List<QueryDocumentSnapshot>> _getUserComments(String userId, List<QueryDocumentSnapshot> topicDocs) async {
    List<QueryDocumentSnapshot> allComments = [];
    
    for (var topicDoc in topicDocs) {
      try {
        final commentsSnapshot = await _db
            .collection('topics')
            .doc(topicDoc.id)
            .collection('comments')
            .where('uid', isEqualTo: userId)
            .get();
        
        for (var commentDoc in commentsSnapshot.docs) {
          // topicId는 doc.reference를 통해 추출 가능하므로 그대로 추가
          allComments.add(commentDoc);
        }
      } catch (e) {
        print("댓글 가져오기 에러 (topicId: ${topicDoc.id}): $e");
      }
    }
    
    return allComments;
  }

  Widget _buildVotesList(String userId, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(userId).collection('votes').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print("❌ 투표 목록 에러: ${snapshot.error}");
          final errorMessage = snapshot.error.toString();
          final isPermissionDenied = errorMessage.contains('permission-denied') || 
                                      errorMessage.contains('PERMISSION_DENIED');
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  isPermissionDenied 
                    ? '투표 목록을 불러올 수 없습니다.\nFirestore 보안 규칙을 확인해주세요.'
                    : '투표 목록을 불러올 수 없습니다: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        print("📊 투표 목록 개수: ${docs.length}");
        
        // 디버깅: 각 투표 정보 출력
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>?;
          print("  - 투표: topicId=${doc.id}, optionIndex=${data?['optionIndex']}, votedAt=${data?['votedAt']}");
        }
        
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.how_to_vote_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('참여한 투표가 없습니다', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('userId: $userId', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          );
        }

        // 클라이언트에서 정렬 (votedAt 기준)
        final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
        sortedDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['votedAt'] as Timestamp?;
          final bTime = bData?['votedAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // 내림차순
        });

        return ListView.builder(
          key: const PageStorageKey<String>('profile_votes'), // 스크롤 위치 유지
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final voteDoc = sortedDocs[index];
            final topicId = voteDoc.id;
            final voteData = voteDoc.data() as Map<String, dynamic>?;
            final optionIndex = voteData?['optionIndex'] as int? ?? 0;
            
            return StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('topics').doc(topicId).snapshots(),
              builder: (context, topicSnapshot) {
                if (topicSnapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                // 에러가 있거나 주제가 존재하지 않으면 아예 표시하지 않음
                if (topicSnapshot.hasError) {
                  return const SizedBox.shrink();
                }

                if (!topicSnapshot.hasData || !topicSnapshot.data!.exists) {
                  return const SizedBox.shrink();
                }

                final topicData = topicSnapshot.data!.data() as Map<String, dynamic>?;
                if (topicData == null) {
                  return const SizedBox.shrink();
                }

                final title = topicData['title'] ?? '제목 없음';
                final options = List<String>.from(topicData['options'] ?? []);
                final optionText = optionIndex < options.length ? options[optionIndex] : '알 수 없음';

                return _buildActivityItem(
                  topicTitle: title,
                  badge: optionText,
                  content: '"$optionText" 에 투표했습니다 !',
                  date: _formatDate(voteData?['votedAt'] as Timestamp?),
                  isDark: isDark,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => VoteScreen(topicId: topicId)),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTopicsList(String userId, bool isDark) {
    print("🔍 주제 목록 조회 - userId: $userId");
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('topics')
          .where('authorId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          print("❌ 주제 목록 에러: ${snapshot.error}");
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('주제 목록을 불러올 수 없습니다: ${snapshot.error}'),
              ],
            ),
          );
        }
        
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        print("📊 주제 목록 개수: ${docs.length}");
        
        // status가 'deleted'인 항목 필터링
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          final status = data?['status'] as String?;
          return status != 'deleted';
        }).toList();
        
        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.topic_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('생성한 주제가 없습니다', style: TextStyle(color: Colors.grey[600])),
                // const SizedBox(height: 8),
                // Text('userId: $userId', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          );
        }

        // 클라이언트에서 정렬 (createdAt 기준)
        final sortedDocs = List<QueryDocumentSnapshot>.from(filteredDocs);
        sortedDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['createdAt'] as Timestamp?;
          final bTime = bData?['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // 내림차순
        });

        return ListView.builder(
          key: const PageStorageKey<String>('profile_topics'), // 스크롤 위치 유지
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length > 50 ? 50 : sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>?;
            if (data == null) return const SizedBox();
            
            final title = data['title'] ?? '제목 없음';
            final category = data['category'] ?? '기타';
            final totalVotes = data['totalVotes'] as int? ?? 0;

            final currentUser = FirebaseAuth.instance.currentUser;
            final isMyTopic = currentUser?.uid == userId;
            
            return _buildActivityItem(
              topicTitle: title,
              badge: category,
              content: '총 $totalVotes표',
              date: _formatDate(data['createdAt'] as Timestamp?),
              isDark: isDark,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => VoteScreen(topicId: doc.id)),
                );
              },
              onDelete: isMyTopic ? () => _deleteTopic(context, doc.id, title) : null,
            );
          },
        );
      },
    );
  }

  Widget _buildTabButton(String label, String count, int index, bool isDark) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFF512F).withOpacity(0.1)
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFF512F)
                  : (isDark ? Colors.white24 : Colors.grey[400]!),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF512F)
                      : (isDark ? Colors.white : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFF512F).withOpacity(0.8)
                      : (isDark ? Colors.white70 : Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 댓글 삭제 함수
  Future<void> _deleteComment(BuildContext context, String topicId, String commentId, bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('이 댓글을 정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Soft Delete: 문서를 삭제하지 않고 isDeleted 플래그와 content를 업데이트
      await _db.collection('topics').doc(topicId).collection('comments').doc(commentId).update({
        'isDeleted': true,
        'content': '삭제된 댓글입니다',
        'author': '알 수 없음',
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('댓글이 삭제되었습니다.')),
        );
      }
    } catch (e) {
      print("❌ 댓글 삭제 에러: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('댓글 삭제에 실패했습니다: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 주제 삭제 함수 (Soft Delete)
  Future<void> _deleteTopic(BuildContext context, String topicId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주제 삭제'),
        content: Text('"$title" 주제를 정말 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Soft Delete: 문서를 삭제하지 않고 status를 'deleted'로 변경
      await _db.collection('topics').doc(topicId).update({
        'status': 'deleted',
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주제가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      print("❌ 주제 삭제 에러: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주제 삭제에 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildActivityItem({
    required String topicTitle,
    required String badge,
    required String content,
    required String date,
    required bool isDark,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2D3A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(topicTitle, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.redAccent),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          // 삭제 버튼 클릭 시 onTap 이벤트 방지
                        },
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          onPressed: () {
                            onDelete();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(content, style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            Text('$date', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '날짜 없음';
    final date = timestamp.toDate();
    return '${date.year}. ${date.month}. ${date.day}.';
  }

  // 사용자 차단 기능
  Future<void> _blockUser(String userId) async {
    // 차단 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사용자 차단'),
        content: const Text('이 사용자를 차단하시겠습니까?\n차단된 사용자의 글과 댓글이 더 이상 보이지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('차단'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _blockService.blockUser(userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 사용자의 글이 더 이상 보이지 않습니다.')),
        );
        // 프로필 화면 닫기
        Navigator.pop(context);
      }
    } catch (e) {
      print('❌ 사용자 차단 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
