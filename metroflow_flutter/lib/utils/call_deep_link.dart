import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/video_call_screen.dart';
import '../services/api.dart';
import '../utils/logger.dart';

/// Deep-link helper for `metricorex://calls/<idOrCode>` — mirrors the web
/// `/join-call?call=<id>&auto=1` push-tap path: resolves the call (UUID or
/// code), REST-joins NON-fatally (the room itself is opened through the
/// socket `call:join` handshake inside VideoCallScreen), then opens the call
/// room full-screen. Used by main.dart's app_links handler and available to
/// push-tap routing for call links.
class CallDeepLinkHelper {
  CallDeepLinkHelper._();

  static Future<void> openCallRoom(BuildContext context, String idOrCode) async {
    final api = ApiService();
    try {
      final detail = await api.getCallDetail(idOrCode);
      final payload = detail.data is Map ? detail.data['data'] : null;
      final callMap = payload is Map && payload['call'] is Map
          ? payload['call'] as Map
          : (payload is Map ? payload : null);
      final callId = (callMap?['id'] ?? idOrCode).toString();
      String? callingRaw;
      String type = (callMap?['type'] ?? 'audio').toString();
      String title = (callMap?['callCode'] ?? '').toString();
      bool isGroupCall = callMap?['isGroupCall'] == true;
      try {
        final join = await api.joinCall(callId);
        final joinData = join.data is Map ? join.data['data'] : null;
        final raw = joinData is Map ? joinData['calling'] : null;
        if (raw is Map) callingRaw = Map<String, dynamic>.from(raw);
        if (joinData is Map) {
          if (joinData['type'] != null) type = joinData['type'].toString();
          if (joinData['callCode'] != null) title = joinData['callCode'].toString();
          if (joinData['isGroupCall'] != null) isGroupCall = joinData['isGroupCall'] == true;
        }
      } on DioException catch (e) {
        // 403 = password gate (deep link without a password cannot proceed).
        final isPassword = e.response?.statusCode == 403;
        Logger.error('Deep-link join failed${isPassword ? ' (password required)' : ''}: $e');
        if (isPassword) return;
        // Non-fatal: still try the room via the socket handshake.
      } catch (e) {
        Logger.error('Deep-link join failed (non-fatal): $e');
      }
      if (!context.mounted) return;
      final userName = await ApiService().storage.getUserName();
      await VideoCallScreen.showModal(
        context: context,
        roomId: callId,
        title: title.isNotEmpty ? title : (type == 'video' ? 'Video Call' : 'Audio Call'),
        enableVideo: type == 'video',
        userName: userName,
        isHost: false,
        isGroupCall: isGroupCall,
        calling: callingRaw,
      );
    } catch (e) {
      Logger.error('Call deep link failed: $e');
      if (context.mounted) {
        GoRouter.of(context).go('/main/calls');
      }
    }
  }
}
