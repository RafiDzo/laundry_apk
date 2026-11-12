import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Background handler wajib berupa top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Service Push Notification terpusat untuk Washora (Customer & Mitra)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentToken;

  /// Callback saat user klik notifikasi (bisa diarahkan ke screen tertentu)
  void Function(Map<String, dynamic> data)? onNotificationTapped;

  /// Inisialisasi awal (panggil di main.dart setelah Firebase.initializeApp)
  Future<void> initialize({void Function(Map<String, dynamic> data)? onTapped}) async {
    if (_initialized) return;
    onNotificationTapped = onTapped;

    // 1. Setup background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (Android 13+ & iOS)
    await _requestPermission();

    // 3. Setup local notification channel (khusus Android)
    await _setupLocalNotifications();

    // 4. Listen foreground message (saat aplikasi sedang dibuka)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Handle saat notifikasi diklik dari background / terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 6. Check jika app dibuka langsung dari notifikasi (terminated state)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }

    // 7. Listen token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      _currentToken = newToken;
      _syncTokenToSupabase(newToken);
    });

    _initialized = true;
  }

  /// Minta izin notifikasi ke sistem
  Future<void> _requestPermission() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  /// Setup saluran notifikasi Android (channel)
  Future<void> _setupLocalNotifications() async {
    const androidChannel = AndroidNotificationChannel(
      'washora_channel',
      'Notifikasi Washora',
      description: 'Saluran notifikasi status cucian, pesanan baru & promo Washora',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettingsAndroid = AndroidInitializationSettings('ic_stat_washora');
    const initSettingsDarwin = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsDarwin,
    );

    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            onNotificationTapped?.call(data);
          } catch (_) {}
        }
      },
    );
  }

  /// Tampilkan popup notifikasi saat aplikasi sedang di foreground
  void _handleForegroundMessage(RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;

    _localNotif.show(
      notif.hashCode,
      notif.title ?? 'Washora',
      notif.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'washora_channel',
          'Notifikasi Washora',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_washora',
          color: Color(0xFF0077B6),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    onNotificationTapped?.call(message.data);
  }

  /// Daftarkan token FCM user saat login ke Supabase
  /// [role]: 'customer' atau 'owner'
  Future<void> registerUserToken(String role) async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;
      _currentToken = token;

      await _syncTokenToSupabase(token, role: role);
    } catch (_) {}
  }

  /// Hapus token FCM dari Supabase saat user logout
  Future<void> unregisterUserToken() async {
    try {
      _currentToken ??= await _fcm.getToken();
      if (_currentToken != null) {
        await Supabase.instance.client.rpc(
          'delete_fcm_token',
          params: {'p_token': _currentToken},
        );
      }
    } catch (_) {}
  }

  /// Sinkronisasi token ke Supabase tabel fcm_tokens
  Future<void> _syncTokenToSupabase(String token, {String role = 'customer'}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web');
      await client.rpc(
        'upsert_fcm_token',
        params: {
          'p_token': token,
          'p_platform': platform,
          'p_role': role,
        },
      );
    } catch (_) {}
  }

  /// Helper untuk subscribe ke topik tertentu (mis. promo broadcast)
  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
  }
}
