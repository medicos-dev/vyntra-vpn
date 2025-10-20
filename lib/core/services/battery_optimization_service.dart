import 'package:flutter/services.dart';

class BatteryOptimizationService {
  static const MethodChannel _channel = MethodChannel('vyntra.battery.optimization');

  /// Request battery optimization exemption
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      print('Error requesting battery optimization exemption: $e');
    }
  }

  /// Check if battery optimization is ignored
  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final result = await _channel.invokeMethod('isBatteryOptimizationIgnored');
      return result ?? false;
    } catch (e) {
      print('Error checking battery optimization status: $e');
      return false;
    }
  }

  /// Open battery optimization settings
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      print('Error opening battery optimization settings: $e');
    }
  }
}
