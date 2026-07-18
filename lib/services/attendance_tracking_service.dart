import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import 'location_address_service.dart';

const _channelId = 'eway_attendance_tracking';
const _notificationId = 4101;

class AttendanceTrackingService {
  AttendanceTrackingService._();
  static final instance = AttendanceTrackingService._();
  final _service = FlutterBackgroundService();

  Future<void> initialize() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
    const channel = AndroidNotificationChannel(_channelId, 'Attendance GPS Tracking', description: 'Shown while EWAY LINK records attendance location.', importance: Importance.low);
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()));
    await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    await _service.configure(
      androidConfiguration: AndroidConfiguration(onStart: attendanceTrackingEntryPoint, autoStart: false, isForegroundMode: true, notificationChannelId: _channelId, initialNotificationTitle: 'EWAY LINK Attendance', initialNotificationContent: 'GPS tracking is active until check-out.', foregroundServiceNotificationId: _notificationId),
      iosConfiguration: IosConfiguration(autoStart: false, onForeground: attendanceTrackingEntryPoint, onBackground: iosAttendanceBackground),
    );
  }

  Future<void> start({required String sessionId, required String employeeId}) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
    if (!await _service.isRunning()) {
      await _service.startService();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _service.invoke('startTracking', {
      'sessionId': sessionId,
      'employeeId': employeeId,
      'refreshToken': Supabase.instance.client.auth.currentSession?.refreshToken,
    });
  }

  void stop() {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) _service.invoke('stopTracking');
  }
}

@pragma('vm:entry-point')
Future<bool> iosAttendanceBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void attendanceTrackingEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  Timer? timer;
  String? sessionId;
  String? employeeId;

  Future<void> record() async {
    if (sessionId == null || employeeId == null) return;
    try {
      final session = await Supabase.instance.client
          .from('attendance_sessions')
          .select('checked_out_at')
          .eq('id', sessionId!)
          .eq('employee_id', employeeId!)
          .maybeSingle();
      if (session == null || session['checked_out_at'] != null) {
        timer?.cancel();
        sessionId = null;
        employeeId = null;
        service.stopSelf();
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 30)));
      final placeName = await LocationAddressService.instance.resolve(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await Supabase.instance.client.from('attendance_location_points').insert({
        'session_id': sessionId,
        'employee_id': employeeId,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'is_mocked': position.isMocked,
        'place_name': placeName,
      });
    } catch (_) {}
  }

  service.on('startTracking').listen((event) async {
    final refreshToken = event?['refreshToken']?.toString();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await Supabase.instance.client.auth.setSession(refreshToken);
    }
    sessionId = event?['sessionId']?.toString();
    employeeId = event?['employeeId']?.toString();
    timer?.cancel();
    record();
    timer = Timer.periodic(const Duration(minutes: 2), (_) => record());
  });
  service.on('stopTracking').listen((_) {
    timer?.cancel();
    service.stopSelf();
  });
}
