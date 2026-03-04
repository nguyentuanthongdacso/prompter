import 'package:flutter/services.dart';

/// Service to communicate with native 2-layer overlay
class NativeOverlayService {
  static const MethodChannel _channel = MethodChannel('com.ntt55.prompter/overlay');
  
  /// Check if overlay permission is granted
  static Future<bool> checkPermission() async {
    try {
      final bool result = await _channel.invokeMethod('checkPermission');
      return result;
    } catch (e) {
      return false;
    }
  }
  
  /// Request overlay permission
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (e) {
      // Handle error
    }
  }
  
  /// Show the overlay with text
  static Future<bool> showOverlay({
    required String text,
    double fontSize = 32.0,
    int textColor = 0xFF000000, // Black
    int speed = 50,
    bool mirrorHorizontal = false,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('showOverlay', {
        'text': text,
        'fontSize': fontSize,
        'textColor': textColor,
        'speed': speed,
        'mirrorHorizontal': mirrorHorizontal,
      });
      return result;
    } catch (e) {
      return false;
    }
  }
  
  /// Hide the overlay
  static Future<bool> hideOverlay() async {
    try {
      final bool result = await _channel.invokeMethod('hideOverlay');
      return result;
    } catch (e) {
      return false;
    }
  }
  
  /// Update the text in overlay
  static Future<bool> updateText(String text) async {
    try {
      final bool result = await _channel.invokeMethod('updateText', {
        'text': text,
      });
      return result;
    } catch (e) {
      return false;
    }
  }
}
