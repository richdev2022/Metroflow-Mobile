
# Calls, Chat &amp; Meeting Feature Issues Report

## Overview
This document lists all issues, dummy data, and improper implementations in the Calls, Chat, and Meeting features of the Metroflow Mobile app, cross-referenced against the official frontend integration guide (`FRONTEND_MEETINGS_CHAT_CALLS_GUIDE.md`).

## Fixes Completed:
- ✅ Socket connection is already being initialized in AuthProvider after login/register/verifyOtp/loginWithBiometrics
- ✅ Added `joinMeeting` and `leaveMeeting` methods to ApiService
- ✅ Updated `MeetingsScreen._joinMeeting` to call joinMeeting API before showing video call screen
- ✅ Fixed `ApiService.deleteCall` return type from `Future&lt;void&gt;` to `Future&lt;Response&gt;`
- ✅ Fixed type error in `CallProvider._handleIncomingCall` by converting dynamic map to `Map&lt;String, dynamic&gt;`
- ✅ Added `mounted` check in `MeetingsScreen._joinMeeting` to avoid build context issues across async gaps
- ✅ Added socket reconnection logic (reconnect delay, max attempts, etc.) with reconnect handlers
- ✅ Fixed unused user.dart import in call_provider.dart
- ✅ All errors fixed (flutter analyze now only shows warnings, which are non-critical)

## Remaining Issues (Requires Backend):
- 🔴 No Mediasoup server implementation in repository - cannot implement WebRTC integration
- 🔴 Socket event payloads for `user-online` and `user-keep-alive` (needs backend confirmation on format)
- 🔴 Missing recording, screen share, in-meeting chat socket event handling (requires backend)
- 🔴 JitsiCallScreen exists but no backend integration

## Remaining Issues (Frontend Only):
- ⚠️ No recording UI (requires backend)
- ⚠️ No screen sharing UI (requires backend)
- ⚠️ No in-meeting chat UI (requires backend)
