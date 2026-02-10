import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../block/block_service.dart'; // ★ BlockService import
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';

class NotificationSettingScreen extends StatefulWidget {
  const NotificationSettingScreen({super.key});

  @override
  State<NotificationSettingScreen> createState() =>
      _NotificationSettingScreenState();
}

class _NotificationSettingScreenState extends State<NotificationSettingScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 알림 설정 상태 변수들
  bool _isProfilePublic = true;
  bool _notifyTopicComments = true; // 내가 생성한 주제에 댓글
  bool _notifyCommentReplies = true; // 내가 단 댓글에 답글
  bool _notifyCommentLikes = false; // 내가 단 댓글에 공감
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Firestore에서 설정 불러오기
  Future<void> _loadSettings() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // 문서가 생성될 때까지 최대 3초 대기 (회원 탈퇴 후 재가입 시 대비)
      // 100ms 간격으로 최대 30회 재시도
      var userDoc = await _db.collection('users').doc(user.uid).get();
      int retries = 0;
      const maxRetries = 30;
      const retryInterval = Duration(milliseconds: 100);

      while (!userDoc.exists && retries < maxRetries) {
        await Future.delayed(retryInterval);
        userDoc = await _db.collection('users').doc(user.uid).get();
        retries++;

        // 문서가 생성되었으면 즉시 처리
        if (userDoc.exists) {
          break;
        }
      }

      if (userDoc.exists) {
        final data = userDoc.data();
        setState(() {
          _isProfilePublic = data?['isPublic'] as bool? ?? true;
          _notifyTopicComments = data?['notifyTopicComments'] as bool? ?? true;
          _notifyCommentReplies =
              data?['notifyCommentReplies'] as bool? ?? true;
          _notifyCommentLikes = data?['notifyCommentLikes'] as bool? ?? false;
          _isLoading = false;
        });
        print("✅ 설정 불러오기 완료 (재시도 ${retries}회)");
      } else {
        // 문서가 없어도 기본값으로 설정하고 로딩 종료
        setState(() {
          _isLoading = false;
        });
        print("⚠️ 사용자 문서 없음, 기본값으로 설정 (재시도 ${retries}회)");
      }
    } catch (e) {
      print("❌ 설정 불러오기 에러: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Firestore에 설정 저장
  Future<void> _saveSettings() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).set({
        'isPublic': _isProfilePublic,
        'notifyTopicComments': _notifyTopicComments,
        'notifyCommentReplies': _notifyCommentReplies,
        'notifyCommentLikes': _notifyCommentLikes,
      }, SetOptions(merge: true));
    } catch (e) {
      print("설정 저장 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장에 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionTitleColor = isDark ? Colors.grey[400] : Colors.grey[700];

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('앱 설정')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('앱 설정', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),),),
      body: ListView(
        children: [
          // ---------------------------------------------------------
          // 1. 공개 범위 설정 섹션
          // ---------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '공개 범위 설정',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sectionTitleColor,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('프로필 공개', style: TextStyle(fontWeight: FontWeight.bold)),
            value: _isProfilePublic,
            activeColor: const Color(0xFFE91E63),
            onChanged: (value) {
              setState(() {
                _isProfilePublic = value;
              });
              _saveSettings();
            },
            secondary: Icon(
              _isProfilePublic ? Icons.lock_open : Icons.lock,
              color: _isProfilePublic ? Colors.green : Colors.grey,
            ),
          ),

          const Divider(height: 40),

          // ---------------------------------------------------------
          // 2. 알림 설정 섹션
          // ---------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '알림 설정',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sectionTitleColor,
              ),
            ),
          ),

          SwitchListTile(
            title: const Text('내가 생성한 주제에 댓글', style: TextStyle(fontWeight: FontWeight.bold)),
            value: _notifyTopicComments,
            activeColor: const Color(0xFFE91E63),
            onChanged: (value) {
              setState(() {
                _notifyTopicComments = value;
              });
              _saveSettings();
            },
            secondary: const Icon(Icons.campaign_outlined),
          ),

          SwitchListTile(
            title: const Text('내가 단 댓글에 답글', style: TextStyle(fontWeight: FontWeight.bold)),
            value: _notifyCommentReplies,
            activeColor: const Color(0xFFE91E63),
            onChanged: (value) {
              setState(() {
                _notifyCommentReplies = value;
              });
              _saveSettings();
            },
            secondary: const Icon(Icons.chat_bubble_outline),
          ),

          SwitchListTile(
            title: const Text('내가 단 댓글에 공감', style: TextStyle(fontWeight: FontWeight.bold)),
            value: _notifyCommentLikes,
            activeColor: const Color(0xFFE91E63),
            onChanged: (value) {
              setState(() {
                _notifyCommentLikes = value;
              });
              _saveSettings();
            },
            secondary: const Icon(Icons.favorite_border),
          ),

          const Divider(height: 40),

          // ---------------------------------------------------------
          // 3. 차단 관리 섹션
          // ---------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '차단 관리',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sectionTitleColor,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('차단한 사용자 관리', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BlockedUsersScreen(),
                ),
              );
            },
          ),

          const Divider(height: 40),

          // ---------------------------------------------------------
          // 4. 회원 탈퇴 섹션
          // ---------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '계정 관리',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sectionTitleColor,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('회원 탈퇴', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('회원 탈퇴'),
                  content: const Text(
                    '정말 탈퇴하시겠습니까?\n모든 활동 내역이 삭제되며 복구할 수 없습니다.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('탈퇴'),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              try {
                await AuthService().deleteAccount();

                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('회원 탈퇴가 완료되었습니다.')),
                  );
                }
              } on FirebaseAuthException catch (e) {
                print(
                  '❌ 회원 탈퇴 에러 (FirebaseAuthException): ${e.code} - ${e.message}',
                );

                if (mounted) {
                  if (e.code == 'requires-recent-login') {
                    await AuthService().signOut();

                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('보안을 위해 다시 로그인이 필요합니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message ?? '회원 탈퇴 중 오류가 발생했습니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                print('❌ 회원 탈퇴 에러: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 차단한 사용자 관리 화면 (BlockService 싱글톤 적용)
// -----------------------------------------------------------------------------
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  // ★ 싱글톤 인스턴스 사용
  final BlockService _blockService = BlockService.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _streamSubscription;

  @override
  void initState() {
    super.initState();
    // 스트림이 비어있을 경우 Firestore에서 직접 로드
    _ensureInitialized();
  }

  Future<void> _ensureInitialized() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // BlockService가 초기화되지 않았을 경우 초기화
    if (_blockService.currentBlockedUsers.isEmpty) {
      try {
        final userDoc = await _db.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          final blockedList = List<String>.from(data?['blockedUsers'] ?? []);
          // BlockService의 내부 상태를 직접 업데이트할 수 없으므로
          // 스트림을 통해 업데이트하도록 유도
          if (blockedList.isNotEmpty) {
            // Firestore 업데이트를 통해 스트림 트리거
            await _db.collection('users').doc(user.uid).update({
              'blockedUsers': blockedList,
            });
          }
        }
      } catch (e) {
        print('⚠️ 차단 목록 초기화 중 오류: $e');
      }
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('차단한 사용자', style: TextStyle(fontWeight: FontWeight.bold))),
      // ★ 실시간 스트림 구독 + Firestore 직접 구독 (이중 보장)
      body: StreamBuilder<DocumentSnapshot>(
        stream: _auth.currentUser != null
            ? _db.collection('users').doc(_auth.currentUser!.uid).snapshots()
            : null,
        builder: (context, userSnapshot) {
          // Firestore에서 차단 목록 가져오기
          List<String> blockedUserIds = [];
          if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final data = userSnapshot.data!.data() as Map<String, dynamic>?;
            blockedUserIds = List<String>.from(data?['blockedUsers'] ?? []);
          } else {
            // 스트림이 아직 로드되지 않았을 경우 BlockService에서 가져오기
            blockedUserIds = _blockService.currentBlockedUsers;
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (blockedUserIds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '차단한 사용자가 없습니다',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: blockedUserIds.length,
            itemBuilder: (context, index) {
              final userId = blockedUserIds[index];

              // 각 차단된 사용자의 닉네임을 가져오기 위한 스트림
              return StreamBuilder<DocumentSnapshot>(
                stream: _db.collection('users').doc(userId).snapshots(),
                builder: (context, userSnapshot) {
                  final userData =
                      userSnapshot.data?.data() as Map<String, dynamic>?;
                  final userName = userData?['nickname'] ?? '알 수 없는 사용자';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2D2D3A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_off_outlined,
                          color: Colors.grey[600],
                        ), // 아이콘 변경
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _unblockUser(userId),
                          child: const Text(
                            '차단 해제',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _unblockUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('차단 해제'),
        content: const Text('이 사용자의 차단을 해제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _blockService.unblockUser(userId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('차단이 해제되었습니다.')));
      }
    } catch (e) {
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
