import 'dart:io';
import 'package:flutter/foundation.dart';

class OverlayService {
  static bool get isOverlaySupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isWindows;
  }

  static bool get isAndroid {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }
}
