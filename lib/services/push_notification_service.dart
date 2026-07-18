import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

const _pushChannelId = 'eway_push_notifications';
const _pushChannelName = 'EWAY LINK Notifications';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> initialize() async {
    if (!_isSupportedPlatform || _initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initializationSettings);

    const channel = AndroidNotificationChannel(
      _pushChannelId,
      _pushChannelName,
      description: 'Attendance, inquiry and cash sales workflow notifications.',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
    _tokenSubscription = _messaging.onTokenRefresh.listen(_registerToken);
    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session != null) registerCurrentDevice();
      },
    );

    if (SupabaseService.client.auth.currentSession != null) {
      await registerCurrentDevice();
    }
  }

  Future<void> registerCurrentDevice() async {
    if (!_isSupportedPlatform || !_initialized) return;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _registerToken(token);
  }

  Future<void> unregisterCurrentDevice() async {
    if (!_isSupportedPlatform || !_initialized) return;
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;

    try {
      await SupabaseService.client.rpc(
        'unregister_push_device',
        params: {'p_token': token},
      );
    } catch (_) {}
  }

  Future<void> _registerToken(String token) async {
    if (SupabaseService.client.auth.currentUser == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';

    try {
      await SupabaseService.client.rpc(
        'register_push_device',
        params: {
          'p_token': token,
          'p_platform': platform,
          'p_app_id': 'com.eway.ewaylink',
        },
      );
    } catch (_) {}
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _pushChannelId,
        _pushChannelName,
        channelDescription:
            'Attendance, inquiry and cash sales workflow notifications.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title ?? 'EWAY LINK',
      body ?? '',
      details,
      payload: message.data['route']?.toString(),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    // Navigation routes are attached to messages and will be connected to
    // specific inquiry and attendance screens in the server-routing phase.
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _initialized = false;
  }
}
