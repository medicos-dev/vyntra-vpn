import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String _sessionKey = 'vpn_session_start';
  static const String _sessionDurationKey = 'vpn_session_duration';
  static const Duration _defaultSessionDuration = Duration(hours: 1);
  
  Timer? _sessionTimer;
  DateTime? _sessionStartTime;
  Duration _sessionDuration = _defaultSessionDuration;
  
  final StreamController<SessionStatus> _statusController = StreamController<SessionStatus>.broadcast();
  final StreamController<Duration> _timeRemainingController = StreamController<Duration>.broadcast();
  
  Stream<SessionStatus> get statusStream => _statusController.stream;
  Stream<Duration> get timeRemainingStream => _timeRemainingController.stream;
  
  SessionStatus get currentStatus => _sessionStartTime != null ? SessionStatus.active : SessionStatus.inactive;
  Duration get timeRemaining {
    if (_sessionStartTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_sessionStartTime!);
    final remaining = _sessionDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  bool get isSessionActive => currentStatus == SessionStatus.active && timeRemaining > Duration.zero;
  
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionStartMillis = prefs.getInt(_sessionKey);
    final sessionDurationMillis = prefs.getInt(_sessionDurationKey);
    
    if (sessionDurationMillis != null) {
      _sessionDuration = Duration(milliseconds: sessionDurationMillis);
    }
    
    if (sessionStartMillis != null) {
      _sessionStartTime = DateTime.fromMillisecondsSinceEpoch(sessionStartMillis);
      if (isSessionActive) {
        _startSessionTimer();
      } else {
        await _endSession();
      }
    }
  }
  
  Future<void> startSession() async {
    _sessionStartTime = DateTime.now();
    await _saveSessionData();
    _startSessionTimer();
    _statusController.add(SessionStatus.active);
  }
  
  Future<void> endSession() async {
    await _endSession();
  }
  
  Future<void> _endSession() async {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionStartTime = null;
    await _clearSessionData();
    _statusController.add(SessionStatus.inactive);
    _timeRemainingController.add(Duration.zero);
  }
  
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = timeRemaining;
      _timeRemainingController.add(remaining);
      
      if (remaining <= Duration.zero) {
        _endSession();
      }
    });
  }
  
  Future<void> _saveSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessionStartTime != null) {
      await prefs.setInt(_sessionKey, _sessionStartTime!.millisecondsSinceEpoch);
    }
    await prefs.setInt(_sessionDurationKey, _sessionDuration.inMilliseconds);
  }
  
  Future<void> _clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
  
  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  void dispose() {
    _sessionTimer?.cancel();
    _statusController.close();
    _timeRemainingController.close();
  }
}

enum SessionStatus { active, inactive, expired }
