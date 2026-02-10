import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme_controller.dart';
import '../profile/profile_screen.dart';
import '../profile/notification_setting_screen.dart';
import '../../features/auth/auth_service.dart';
import '../../utils/profanity_filter.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 배경색 설정 (다크모드일 때 더 진한 색으로)
    final backgroundColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF2D2D3A) : Colors.grey[100];

    return Drawer(
      backgroundColor: backgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 커스텀 프로필 헤더 (기존 그라데이션 박스 제거)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
              child: StreamBuilder<DocumentSnapshot>(
                stream: user != null
                    ? db.collection('users').doc(user.uid).snapshots()
                    : null,
                builder: (context, snapshot) {
                  String displayName = '익명 유저';
                  String displayEmail = '로그인해주세요';

                  if (user != null) {
                    displayEmail = user.email ?? '이메일 없음';
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      displayName = data?['nickname'] ?? '익명 유저';
                    } else if (snapshot.connectionState == ConnectionState.waiting) {
                      displayName = '...';
                    }
                  }

                  return Row(
                    children: [
                      // 프로필 이미지 (그림자 효과 추가)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: surfaceColor,
                          child: Text(
                            displayName.isNotEmpty ? displayName[0] : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 이름 및 이메일
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: user != null
                                  ? () => _showEditNicknameDialog(
                                        context,
                                        currentNickname: displayName,
                                        userId: user.uid,
                                      )
                                  : null,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (user != null) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayEmail,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
            
            // 구분선 (살짝 여백 있게)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: isDark ? Colors.white10 : Colors.grey[200]),
            ),
            
            const SizedBox(height: 10),

            // 2. 메뉴 리스트 (둥근 버튼 스타일)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    _buildMenuItem(
                      context,
                      icon: Icons.person_outline_rounded,
                      title: '내 활동',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        if (user != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildMenuItem(
                      context,
                      icon: Icons.notifications_outlined,
                      title: '앱 설정',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationSettingScreen(),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 다크모드 스위치 (커스텀 스타일)
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeNotifier,
                      builder: (context, currentThemeMode, child) {
                        final isDarkMode = currentThemeMode == ThemeMode.dark;
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black26 : Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                                color: isDark ? const Color.fromARGB(255, 255, 217, 0) : Colors.orange,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              '다크 모드',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            trailing: Switch(
                              value: isDarkMode,
                              onChanged: (value) => toggleTheme(),
                              activeColor: const Color(0xFFFF512F),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 3. 하단 로그아웃 버튼 (강조됨)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2D3A) : Colors.red[50],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  onTap: () async {
                    Navigator.pop(context);
                    await AuthService().signOut();
                  },
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text(
                    '퇴장하기',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 메뉴 아이템 빌더 (재사용 위젯)
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // 선택된 느낌을 주고 싶으면 여기에 배경색 추가 가능
          ),
          child: Row(
            children: [
              // 아이콘 배경 박스
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  // 닉네임 편집 다이얼로그
  Future<void> _showEditNicknameDialog(
    BuildContext context, {
    required String currentNickname,
    required String userId,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final db = FirebaseFirestore.instance;
    final TextEditingController nicknameController =
        TextEditingController(text: currentNickname);
    String? errorMessage;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D3A) : Colors.white,
          title: Text(
            '닉네임 수정',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nicknameController,
                enabled: !isLoading,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: '닉네임',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  hintText: '2~10자 이내로 입력해주세요',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Color(0xFFFF512F),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Colors.red,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Colors.red,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorText: errorMessage,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E2C) : Colors.grey[50],
                ),
                onChanged: (value) {
                  if (errorMessage != null) {
                    setDialogState(() {
                      errorMessage = null;
                    });
                  }
                },
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF512F)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                    },
              child: Text(
                '취소',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final newNickname = nicknameController.text.trim();

                      // 클라이언트 측 유효성 검사
                      if (newNickname.isEmpty) {
                        setDialogState(() {
                          errorMessage = '닉네임을 입력해주세요.';
                        });
                        return;
                      }

                      if (newNickname.length < 2 || newNickname.length > 10) {
                        setDialogState(() {
                          errorMessage = '닉네임은 2자 이상 10자 이하여야 합니다.';
                        });
                        return;
                      }

                      // 정규식 검사: 한글, 영문, 숫자만 허용
                      final RegExp validPattern = RegExp(r'^[가-힣a-zA-Z0-9]+$');
                      if (!validPattern.hasMatch(newNickname)) {
                        setDialogState(() {
                          errorMessage = '한글, 영문, 숫자만 사용할 수 있습니다.';
                        });
                        return;
                      }

                      // 욕설 필터링 검사
                      if (ProfanityFilter.hasProfanity(newNickname)) {
                        setDialogState(() {
                          errorMessage = '비속어가 포함되어 있습니다.';
                        });
                        return;
                      }

                      // 현재 닉네임과 동일하면 업데이트 불필요
                      if (newNickname == currentNickname) {
                        Navigator.pop(dialogContext);
                        return;
                      }

                      // 로딩 시작
                      setDialogState(() {
                        isLoading = true;
                        errorMessage = null;
                      });

                      try {
                        // 중복 체크
                        final duplicateQuery = await db
                            .collection('users')
                            .where('nickname', isEqualTo: newNickname)
                            .get();

                        if (duplicateQuery.docs.isNotEmpty) {
                          // 자기 자신의 닉네임이 아닌 경우에만 중복으로 판단
                          final existingDoc = duplicateQuery.docs.first;
                          if (existingDoc.id != userId) {
                            setDialogState(() {
                              isLoading = false;
                              errorMessage = '이미 사용 중인 닉네임입니다.';
                            });
                            return;
                          }
                        }

                        // 1. Firestore 사용자 프로필 업데이트
                        await db.collection('users').doc(userId).update({
                          'nickname': newNickname,
                        });

                        // 2. 모든 댓글의 닉네임 일괄 업데이트 (Batch Update)
                        try {
                          // 모든 topics 가져오기
                          final topicsSnapshot = await db.collection('topics').get();
                          
                          // WriteBatch 초기화
                          WriteBatch batch = db.batch();
                          int batchCount = 0;
                          const int maxBatchSize = 500; // Firestore 배치 제한

                          // 각 topic의 comments 서브컬렉션에서 해당 사용자의 댓글 찾기
                          for (var topicDoc in topicsSnapshot.docs) {
                            final commentsSnapshot = await db
                                .collection('topics')
                                .doc(topicDoc.id)
                                .collection('comments')
                                .where('uid', isEqualTo: userId)
                                .get();

                            // 각 댓글에 대해 배치 업데이트 추가
                            for (var commentDoc in commentsSnapshot.docs) {
                              final commentRef = db
                                  .collection('topics')
                                  .doc(topicDoc.id)
                                  .collection('comments')
                                  .doc(commentDoc.id);
                              
                              batch.update(commentRef, {'author': newNickname});
                              batchCount++;

                              // 배치 크기 제한 체크 (500개마다 커밋)
                              if (batchCount >= maxBatchSize) {
                                await batch.commit();
                                batch = db.batch(); // 새 배치 시작
                                batchCount = 0;
                              }
                            }
                          }

                          // 남은 배치 커밋
                          if (batchCount > 0) {
                            await batch.commit();
                          }

                          print('✅ 닉네임 및 댓글 업데이트 완료: $newNickname');
                        } catch (e) {
                          // 댓글 업데이트 실패해도 사용자 프로필은 업데이트되었으므로 계속 진행
                          print('⚠️ 댓글 닉네임 업데이트 중 오류 발생: $e');
                          // 사용자에게는 성공 메시지 표시 (프로필은 업데이트되었으므로)
                        }

                        // 성공
                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                '닉네임이 변경되었습니다.',
                                style: TextStyle(color: Colors.white),
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF2D2D3A)
                                  : Colors.grey[800],
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                          errorMessage = '닉네임 변경에 실패했습니다. 다시 시도해주세요.';
                        });
                      }
                    },
              child: Text(
                '저장',
                style: TextStyle(
                  color: isLoading
                      ? (isDark ? Colors.grey[600] : Colors.grey[400])
                      : const Color(0xFFFF512F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}