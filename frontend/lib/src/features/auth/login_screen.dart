import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'auth_service.dart';
import '../feed/feed_screen.dart';
import 'nickname_screen.dart'; // ★ 추가됨

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // 공통 로그인 처리 로직
  void _processLogin(Future<dynamic> loginFunction) async {
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

      // ★ [제재 체크] 로그인 성공 직후 제재 상태 확인
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

      // ★ [핵심 수정] 프로필 존재 여부 확인
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
                const SizedBox(height: 60),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  // 구글 로그인 (위로 이동)
                  GestureDetector(
                    onTap: () => _processLogin(AuthService().signInWithGoogle()),
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
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
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
                  // 애플 로그인 (iOS에서만 표시)
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _processLogin(AuthService().signInWithApple()),
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
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
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
