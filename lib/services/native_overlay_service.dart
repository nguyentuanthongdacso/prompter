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
  
  /// Show the overlay with all settings
  static Future<bool> showOverlay({
    required String text,
    double fontSize = 32.0,
    int textColor = 0xFF000000,
    int backgroundColor = 0x00000000,
    int speed = 50,
    bool mirrorHorizontal = false,
    String fontFamily = 'Roboto',
    bool isBold = false,
    bool isItalic = false,
    double lineHeight = 1.5,
    int textAlign = 1, // 0=left, 1=center, 2=right
    double opacity = 0.0,
    double paddingHorizontal = 20.0,
    int overlayPosition = 2, // 0=top, 1=center, 2=bottom
    double overlayHeight = 150.0,
    int scrollMode = 0,
    String fontFilePath = '',
    double initialProgress = 0.0,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('showOverlay', {
        'text': text,
        'fontSize': fontSize,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
        'speed': speed,
        'mirrorHorizontal': mirrorHorizontal,
        'fontFamily': fontFamily,
        'isBold': isBold,
        'isItalic': isItalic,
        'lineHeight': lineHeight,
        'textAlign': textAlign,
        'opacity': opacity,
        'paddingHorizontal': paddingHorizontal,
        'overlayPosition': overlayPosition,
        'overlayHeight': overlayHeight,
        'scrollMode': scrollMode,
        'fontFilePath': fontFilePath,
        'initialProgress': initialProgress,
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

  /// Update all overlay settings live (rebuilds overlay view)
  static Future<bool> updateSettings({
    required String text,
    double fontSize = 32.0,
    int textColor = 0xFF000000,
    int backgroundColor = 0x00000000,
    int speed = 50,
    bool mirrorHorizontal = false,
    String fontFamily = 'Roboto',
    bool isBold = false,
    bool isItalic = false,
    double lineHeight = 1.5,
    int textAlign = 1,
    double opacity = 0.0,
    double paddingHorizontal = 20.0,
    int overlayPosition = 2,
    double overlayHeight = 150.0,
    int scrollMode = 0,
    String fontFilePath = '',
  }) async {
    try {
      final bool result = await _channel.invokeMethod('updateSettings', {
        'text': text,
        'fontSize': fontSize,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
        'speed': speed,
        'mirrorHorizontal': mirrorHorizontal,
        'fontFamily': fontFamily,
        'isBold': isBold,
        'isItalic': isItalic,
        'lineHeight': lineHeight,
        'textAlign': textAlign,
        'opacity': opacity,
        'paddingHorizontal': paddingHorizontal,
        'overlayPosition': overlayPosition,
        'overlayHeight': overlayHeight,
        'scrollMode': scrollMode,
        'fontFilePath': fontFilePath,
      });
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Check if overlay is currently running
  static Future<bool> isOverlayRunning() async {
    try {
      final bool result = await _channel.invokeMethod('isOverlayRunning');
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Get current overlay state (speed, textColor changed from overlay controls)
  static Future<Map<String, dynamic>?> getOverlayState() async {
    try {
      final result = await _channel.invokeMethod('getOverlayState');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Toggle play/pause on the overlay without rebuilding it
  static Future<void> togglePlayPause() async {
    try {
      await _channel.invokeMethod('overlayPlayPause');
    } catch (_) {}
  }

  /// Rewind scroll (back 200px) on the overlay
  static Future<void> resetScroll() async {
    try {
      await _channel.invokeMethod('overlayResetScroll');
    } catch (_) {}
  }

  /// Reset scroll to the very beginning (position 0) on the overlay
  static Future<void> resetToStart() async {
    try {
      await _channel.invokeMethod('overlayResetToStart');
    } catch (_) {}
  }

  /// Scroll forward on the overlay
  static Future<void> scrollForward() async {
    try {
      await _channel.invokeMethod('overlayScrollForward');
    } catch (_) {}
  }
}
