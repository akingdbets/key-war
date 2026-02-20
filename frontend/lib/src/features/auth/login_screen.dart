import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'auth_service.dart';
import '../feed/feed_screen.dart';
import 'nickname_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  // ★ 약관 동의 체크 여부를 저장하는 변수 추가
  bool _isEulaAccepted = false;

  // 공통 로그인 처리 로직
  void _processLogin(Future<dynamic> loginFunction) async {
    // ★ 약관에 동의하지 않았으면 스낵바로 알림 띄우고 로그인 진행 막음
    if (!_isEulaAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('서비스 이용약관(EULA)에 동의해야 시작할 수 있습니다.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await loginFunction;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // [제재 체크] 로그인 성공 직후 제재 상태 확인
      final authService = AuthService();
      final isAllowed = await authService.checkUserStatus(user.uid);

      if (!isAllowed) {
        // 제재된 유저: 로그인 차단
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '운영 정책 위반으로 계정이 정지되었습니다.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('운영 정책 위반으로 계정이 정지되었습니다.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // [핵심 수정] 프로필 존재 여부 확인
      final exists = await authService.hasProfile(user.uid);

      if (mounted) {
        if (exists) {
          // 기존 유저 -> 메인 화면
          Navigator.of(context, rootNavigator: true).pushReplacement(
            MaterialPageRoute(builder: (context) => const FeedScreen()),
          );
        } else {
          // 신규 유저 -> 닉네임 설정 화면
          Navigator.of(context, rootNavigator: true).pushReplacement(
            MaterialPageRoute(builder: (context) => NicknameScreen(user: user)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // ★ 애플이 요구하는 "무관용 원칙"이 포함된 약관을 보여주는 다이얼로그 함수
  void _showEulaDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D3A),
          title: const Text(
            '서비스 이용약관 (EULA)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const SingleChildScrollView(
            child: Text(
              '''본 앱을 이용하기 위해 아래 약관에 동의해야 합니다.

1. 이용자의 의무
사용자는 본 서비스를 이용함에 있어 관련 법령, 본 약관, 사회적 통념을 준수해야 합니다.

2. 불쾌한 콘텐츠 및 악성 이용자에 대한 무관용 원칙 (No Tolerance)
본 서비스는 타인에게 불쾌감을 주는 콘텐츠(욕설, 비방, 차별, 음란물 등) 및 악의적인 이용자(어뷰징, 스팸 등)에 대해 '무관용 원칙(No tolerance)'을 엄격하게 적용합니다. 

부적절한 콘텐츠를 게시하거나 타인을 괴롭히는 행위가 적발될 경우, 사전 경고 없이 즉시 해당 콘텐츠는 삭제되며 해당 이용자의 계정은 영구적으로 차단(이용 정지)됩니다.

3. 콘텐츠 필터링 및 신고
모든 사용자는 불쾌한 콘텐츠나 악성 유저를 즉시 신고하고 차단할 수 있는 기능을 사용할 수 있습니다. 운영진은 신고 접수 후 24시간 이내에 이를 검토하고 필요한 조치를 취할 의무가 있습니다.''',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isEulaAccepted = true; // 약관 보고 닫으면 자동으로 동의 체크
                });
              },
              child: const Text(
                '확인 및 동의',
                style: TextStyle(
                  color: Color(0xFFFF512F),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF191919), // 깊은 웜 차콜 그레이
              Color(0xFF000000), // 거의 완전한 블랙
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/icon/icon.png', width: 120, height: 120),
                const SizedBox(height: 20),
                const Text(
                  "KEY WAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "입으로만 싸우지 말고, 손가락으로 증명하라",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 40),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                // ★ 약관 동의 체크박스 영역 추가
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    children: [
                      Theme(
                        data: ThemeData(
                          unselectedWidgetColor: Colors.grey, // 체크 안된 상태의 박스 색상
                        ),
                        child: Checkbox(
                          value: _isEulaAccepted,
                          checkColor: Colors.white,
                          activeColor: const Color(0xFFFF512F),
                          onChanged: (bool? value) {
                            setState(() {
                              _isEulaAccepted = value ?? false;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showEulaDialog,
                          child: const Text.rich(
                            TextSpan(
                              text: '서비스 이용약관(EULA)',
                              style: TextStyle(
                                color: Color(0xFFFF512F),
                                decoration: TextDecoration.underline,
                                fontSize: 13,
                              ),
                              children: [
                                TextSpan(
                                  text: '에 동의합니다.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  // 구글 로그인 (버튼 투명도를 약관 동의 여부에 따라 조절)
                  GestureDetector(
                    onTap: () =>
                        _processLogin(AuthService().signInWithGoogle()),
                    child: Opacity(
                      opacity: _isEulaAccepted ? 1.0 : 0.5, // 동의 안했으면 반투명하게
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                              height: 24,
                              width: 24,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.g_mobiledata,
                                  size: 24,
                                  color: Colors.black87,
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.grey,
                                            ),
                                      ),
                                    );
                                  },
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              "Google로 시작하기",
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 애플 로그인 (iOS 및 Web에서 모두 노출)
                  if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () =>
                          _processLogin(AuthService().signInWithApple()),
                      child: Opacity(
                        opacity: _isEulaAccepted ? 1.0 : 0.5, // 동의 안했으면 반투명하게
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network(
                                'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Apple_logo_black.svg/800px-Apple_logo_black.svg.png',
                                height: 24,
                                width: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.apple,
                                    size: 24,
                                    color: Colors.black87,
                                  );
                                },
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.grey,
                                              ),
                                        ),
                                      );
                                    },
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                "Apple로 시작하기",
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
