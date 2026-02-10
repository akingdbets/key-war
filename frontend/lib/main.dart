import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // ★ 아까 만든 열쇠 파일
import 'src/app.dart';
import 'src/core/fcm_service.dart';
import 'src/features/block/block_service.dart'; // ★ BlockService import 추가

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // ★ 파이어베이스 서버 연결 (자동 생성된 설정 사용)
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('✅ Firebase 초기화 완료');

    // Firestore 설정 (오프라인 지속성 활성화)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // FCM 초기화
    try {
      await FCMService().initialize();
      print('✅ FCM 초기화 완료');
    } catch (e) {
      print('❌ FCM 초기화 실패: $e');
      // FCM 초기화 실패해도 앱은 계속 실행
    }

    // ★ 차단 서비스 초기화 (앱 시작 시 차단 목록 불러오기 및 실시간 리스너 연결)
    try {
      await BlockService.instance.init();
      print('✅ 차단 서비스 초기화 완료');
    } catch (e) {
      print('❌ 차단 서비스 초기화 실패: $e');
      // 차단 서비스 초기화 실패해도 앱은 계속 실행
    }

    print('🚀 앱 시작 중...');
    runApp(const MyApp());
  } catch (e, stackTrace) {
    print('❌ 앱 초기화 중 치명적 에러 발생: $e');
    print('❌ 스택 트레이스: $stackTrace');
    // 에러가 발생해도 앱은 실행되도록 함
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('앱 초기화 중 오류가 발생했습니다.\n$e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // 앱 재시작 시도
                  main();
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
