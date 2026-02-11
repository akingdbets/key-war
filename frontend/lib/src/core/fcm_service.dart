import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../utils/notification_state.dart';

// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("백그라운드 메시지 수신: ${message.messageId}");
  print("제목: ${message.notification?.title}");
  print("내용: ${message.notification?.body}");
  print("데이터: ${message.data}");
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _fcmToken;
  
  // 로컬 알림 플러그인 인스턴스
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // 알림 채널 ID (Android용)
  static const String _notificationChannelId = 'key_war_notifications';
  static const String _notificationChannelName = 'Key War 알림';
  static const String _notificationChannelDescription = '투표 및 댓글 알림을 받습니다.';

  // FCM 초기화
  Future<void> initialize() async {
    try {
      print('🔔 FCM 초기화 시작...');
      
      // 로컬 알림 초기화
      await _initializeLocalNotifications();
      
      // 알림 권한 요청 (iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ 사용자가 알림 권한을 허용했습니다');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ 사용자가 임시 알림 권한을 허용했습니다');
      } else {
        print('❌ 사용자가 알림 권한을 거부했습니다');
        return;
      }

      // FCM 토큰 가져오기
      _fcmToken = await _messaging.getToken();
      print('🔑 FCM 토큰: $_fcmToken');

      if (_fcmToken == null) {
        print('❌ FCM 토큰을 가져올 수 없습니다');
        return;
      }

      // 토큰을 Firestore에 저장
      await _saveTokenToFirestore(_fcmToken);
    } catch (e) {
      print('❌ FCM 초기화 에러: $e');
    }

    // 토큰 갱신 리스너
    _messaging.onTokenRefresh.listen((newToken) {
      print('FCM 토큰 갱신: $newToken');
      _fcmToken = newToken;
      _saveTokenToFirestore(newToken);
    });

    // 포그라운드 메시지 핸들러
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 포그라운드 메시지 수신: ${message.messageId}');
      print('제목: ${message.notification?.title}');
      print('내용: ${message.notification?.body}');
      print('데이터: ${message.data}');
      
      // 알림 데이터에서 voteId 추출 (topicId 또는 voteId 필드 확인)
      final voteId = message.data['voteId'] ?? message.data['topicId'];
      
      // 현재 보고 있는 투표방인지 확인
      if (NotificationState.isViewingVote(voteId)) {
        print('⏭️ 현재 보고 있는 방이라 알림 생략: voteId=$voteId');
        return;
      }
      
      // 다른 방의 알림이면 로컬 알림 표시
      _showLocalNotification(message);
    });

    // 백그라운드 메시지 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 알림 클릭 핸들러는 MyApp의 initState에서 처리합니다
  }

  // Firestore에 FCM 토큰 저장
  Future<void> _saveTokenToFirestore(String? token) async {
    final user = _auth.currentUser;
    if (user == null) {
      print('❌ FCM 토큰 저장 실패: 사용자가 로그인하지 않았습니다');
      return;
    }
    if (token == null) {
      print('❌ FCM 토큰 저장 실패: 토큰이 null입니다');
      return;
    }

    try {
      print('💾 FCM 토큰 저장 시도: userId=${user.uid}, token=${token.substring(0, 20)}...');
      await _db.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('✅ FCM 토큰을 Firestore에 저장했습니다');
    } catch (e) {
      print('❌ FCM 토큰 저장 에러: $e');
      print('❌ 에러 상세: ${e.toString()}');
    }
  }

  // FCM 토큰 가져오기
  String? get token => _fcmToken;

  // 특정 사용자에게 알림 전송 (서버 측에서 호출해야 함)
  // 클라이언트에서는 Firestore에 알림 데이터를 저장하고,
  // Cloud Functions에서 FCM으로 푸시 알림을 전송하는 것이 일반적입니다
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // 클라이언트에서는 Firestore에 알림 데이터만 저장
    // 실제 FCM 푸시는 Cloud Functions에서 처리해야 합니다
    try {
      await _db.collection('users').doc(targetUserId).collection('notifications').add({
        'type': data?['type'] ?? 'general',
        'message': body,
        'title': title,
        'topicId': data?['topicId'],
        'commentId': data?['commentId'],
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('알림 저장 에러: $e');
    }
  }

  // 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    // Android 초기화 설정
    // drawable/ic_notification.png 파일이 필요합니다 (확장자 없이 파일명만)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_notification');
    
    // iOS 초기화 설정
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    // 초기화 설정
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    // 초기화
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('로컬 알림 클릭: ${response.payload}');
        // 알림 클릭 시 처리 로직은 필요에 따라 추가
      },
    );
    
    // Android 알림 채널 생성 (Android 8.0 이상)
    if (!kIsWeb && Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _notificationChannelId,
        _notificationChannelName,
        description: _notificationChannelDescription,
        importance: Importance.max, // 최대 중요도로 설정하여 헤드업 알림 표시
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      
      print('✅ Android 알림 채널 생성 완료: $_notificationChannelId');
    }
  }

  // 로컬 알림 표시
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final title = message.notification?.title ?? 'Key War';
      final body = message.notification?.body ?? '';
      final data = message.data;
      
      // 알림 ID 생성 (중복 방지)
      final notificationId = message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch;
      
      // Android 알림 상세 설정
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _notificationChannelId,
        _notificationChannelName,
        channelDescription: _notificationChannelDescription,
        importance: Importance.max, // 헤드업 알림 표시
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: 'ic_notification', // 알림 아이콘 지정 (작은 아이콘 - 알림 바, drawable 폴더의 파일명, 확장자 없이)
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'), // 큰 아이콘 (알림 펼쳤을 때)
      );
      
      // iOS 알림 상세 설정
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      // 플랫폼별 알림 상세 설정
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // 알림 표시
      await _localNotifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: data.toString(), // 알림 클릭 시 전달할 데이터
      );
      
      print('✅ 로컬 알림 표시 완료: title=$title, body=$body');
    } catch (e) {
      print('❌ 로컬 알림 표시 에러: $e');
    }
  }
}

