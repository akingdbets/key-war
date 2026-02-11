import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 추가
import 'package:firebase_messaging/firebase_messaging.dart';
import 'features/feed/feed_screen.dart';
import 'features/auth/login_screen.dart'; // 추가
import 'features/auth/auth_service.dart'; // 추가
import 'features/vote/vote_screen.dart'; // VoteScreen으로 이동
import 'core/theme_controller.dart'; // 테마 컨트롤러

// 전역 네비게이터 키 (알림 클릭 시 화면 이동용)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 스트림 변수 캐싱 (테마 변경 시에도 스트림 연결 유지)
  // late final 대신 초기화를 즉시 수행하여 LateInitializationError 방지
  final Stream<User?> _authStream = AuthService().authStateChanges;
  
  @override
  void initState() {
    super.initState();
    
    // 푸시 알림 클릭 처리 초기화
    _initNotificationHandlers();
  }
  
  // 푸시 알림 클릭 핸들러 초기화
  void _initNotificationHandlers() {
    // 앱이 종료된 상태에서 알림 클릭으로 열린 경우
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('🔔 앱 종료 상태에서 알림 클릭으로 열림: ${message.messageId}');
        print('📋 데이터: ${message.data}');
        // 앱이 완전히 초기화된 후에 처리
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationClick(message.data);
        });
      }
    });
    
    // 앱이 백그라운드에 있을 때 알림 클릭
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🔔 알림 클릭으로 앱 열림: ${message.messageId}');
      print('📋 데이터: ${message.data}');
      _handleNotificationClick(message.data);
    });
  }
  
  // 알림 클릭 처리 (VoteScreen으로 이동)
  void _handleNotificationClick(Map<String, dynamic> data) {
    final String? topicId = data['topicId'] as String?;
    
    if (topicId != null && topicId.isNotEmpty) {
      print('📍 VoteScreen으로 이동: topicId=$topicId');
      
      // navigatorKey를 사용하여 전역에서 네비게이션
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VoteScreen(topicId: topicId),
          ),
        );
      } else {
        print('⚠️ Navigator context를 가져올 수 없습니다.');
        // context가 아직 준비되지 않았다면 잠시 후 재시도
        Future.delayed(const Duration(milliseconds: 500), () {
          final retryContext = navigatorKey.currentContext;
          if (retryContext != null) {
            Navigator.of(retryContext).push(
              MaterialPageRoute(
                builder: (context) => VoteScreen(topicId: topicId),
              ),
            );
          }
        });
      }
    } else {
      print('⚠️ topicId가 없어 VoteScreen으로 이동할 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder로 테마 변경 시에도 화면 리셋 방지
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey, // 전역 네비게이터 키 설정
          title: 'Key War',
          theme: ThemeData(
            useMaterial3: true,
            primarySwatch: Colors.blue,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: themeMode, // ValueListenableBuilder에서 받은 themeMode 사용
          
          // ★ 여기가 핵심 문지기!
          home: StreamBuilder<User?>(
            stream: _authStream, // 캐싱된 스트림 사용 (테마 변경 시에도 연결 유지)
            builder: (context, snapshot) {
              // 에러 처리
              if (snapshot.hasError) {
                print('❌ 인증 스트림 에러: ${snapshot.error}');
                // 에러가 발생해도 로그인 화면으로 이동
                return const LoginScreen();
              }
              
              // 1. 아직 로딩 중이면?
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  body: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF191919),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                );
              }
              
              // 2. 로그인 정보가 있으면? -> 피드 화면(Main)
              if (snapshot.hasData && snapshot.data != null) {
                return const FeedScreen();
              }
              
              // 3. 없으면? -> 로그인 화면
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}