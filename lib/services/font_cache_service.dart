import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads Google Font TTF files and caches them locally
/// so the native Android overlay can load them via Typeface.createFromFile().
class FontCacheService {
  static final Map<String, String> _pathCache = {};

  // Fonts handled by Android system font mapping — no download needed
  static const _androidSystemFonts = {
    'Roboto', 'Arial', 'Times New Roman',
  };

  /// Returns the local file path of the downloaded TTF for the given font,
  /// or null if download fails (the native side will fall back to system font).
  static Future<String?> ensureFontFile(
    String fontFamily, {
    bool isBold = false,
    bool isItalic = false,
  }) async {
    // System fonts are mapped on the Kotlin side — no file needed
    if (_androidSystemFonts.contains(fontFamily)) return null;

    final weight = isBold ? '700' : '400';
    final variant = '${weight}_${isItalic ? 'italic' : 'normal'}';
    final key = '${fontFamily}_$variant';

    // Check in-memory cache first
    if (_pathCache.containsKey(key)) {
      final cached = _pathCache[key]!;
      if (File(cached).existsSync() && File(cached).lengthSync() > 1000) {
        return cached;
      }
      _pathCache.remove(key);
    }

    try {
      final dir = await getTemporaryDirectory();
      final fontsDir = Directory('${dir.path}/overlay_fonts');
      if (!fontsDir.existsSync()) {
        fontsDir.createSync(recursive: true);
      }

      final safeName = fontFamily.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${fontsDir.path}/${safeName}_$variant.ttf');

      // Already downloaded and valid
      if (file.existsSync() && _isValidFontFile(file)) {
        _pathCache[key] = file.path;
        return file.path;
      }

      // Delete invalid cached file if exists
      if (file.existsSync()) file.deleteSync();

      // Download from Google Fonts API
      final downloaded = await _downloadFont(fontFamily, weight, isItalic, file);
      if (downloaded && _isValidFontFile(file)) {
        _pathCache[key] = file.path;
        debugPrint('[FontCache] OK: $fontFamily -> ${file.path}');
        return file.path;
      }

      // Clean up invalid download
      if (file.existsSync()) file.deleteSync();
      debugPrint('[FontCache] FAILED: Could not download $fontFamily');
      return null;
    } catch (e, st) {
      debugPrint('[FontCache] Error for $fontFamily: $e\n$st');
      return null;
    }
  }

  /// Try downloading from Google Fonts using CSS API v1 and v2
  static Future<bool> _downloadFont(
    String fontFamily, String weight, bool isItalic, File outputFile,
  ) async {
    // Use + for spaces — standard for Google Fonts API
    final familyParam = fontFamily.replaceAll(' ', '+');

    // CSS v1: simpler format, better TTF compatibility with old user agents
    final v1Style = isItalic ? '${weight}italic' : weight;
    // CSS v2: newer format
    final italicVal = isItalic ? '1' : '0';

    final cssUrls = [
      'https://fonts.googleapis.com/css?family=$familyParam:$v1Style',
      'https://fonts.googleapis.com/css2?family=$familyParam:ital,wght@$italicVal,$weight',
    ];

    // Old user agents that make Google Fonts return TTF instead of WOFF2
    final userAgents = [
      'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Trident/4.0)',
      'Mozilla/5.0 (Linux; U; Android 4.0; en-us) AppleWebKit/534.30',
    ];

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      for (final cssUrlStr in cssUrls) {
        for (final ua in userAgents) {
          try {
            debugPrint('[FontCache] Trying: $cssUrlStr');
            final cssRequest = await client.getUrl(Uri.parse(cssUrlStr));
            cssRequest.headers.set('User-Agent', ua);
            final cssResponse = await cssRequest.close();

            if (cssResponse.statusCode != 200) {
              debugPrint('[FontCache] CSS status: ${cssResponse.statusCode}');
              await cssResponse.drain<void>();
              continue;
            }

            final cssBody = await cssResponse.transform(utf8.decoder).join();

            // Prefer .ttf URLs, then fall back to any font URL
            String? fontUrl;
            final ttfMatch = RegExp(
              r"url\((https://fonts\.gstatic\.com/[^)]+\.ttf)\)",
            ).firstMatch(cssBody);
            if (ttfMatch != null) {
              fontUrl = ttfMatch.group(1);
            } else {
              final anyMatch = RegExp(
                r"url\((https://fonts\.gstatic\.com/[^)]+)\)",
              ).firstMatch(cssBody);
              fontUrl = anyMatch?.group(1);
            }

            if (fontUrl == null) {
              debugPrint('[FontCache] No font URL in CSS response');
              continue;
            }

            debugPrint('[FontCache] Downloading: $fontUrl');
            final fontRequest = await client.getUrl(Uri.parse(fontUrl));
            fontRequest.headers.set('User-Agent', ua);
            final fontResponse = await fontRequest.close();

            if (fontResponse.statusCode != 200) {
              debugPrint('[FontCache] Font HTTP ${fontResponse.statusCode}');
              await fontResponse.drain<void>();
              continue;
            }

            final builder = BytesBuilder();
            await fontResponse.forEach(builder.add);
            final bytes = builder.toBytes();

            if (bytes.length < 1000) {
              debugPrint('[FontCache] File too small: ${bytes.length} bytes');
              continue;
            }

            // Validate magic bytes: TTF, OTF, or TTC
            if (!_isValidFontBytes(bytes)) {
              debugPrint(
                '[FontCache] Invalid font format (first 4 bytes: '
                '${bytes.take(4).map((b) => '0x${b.toRadixString(16)}').join(', ')})',
              );
              continue;
            }

            await outputFile.writeAsBytes(bytes);
            debugPrint('[FontCache] Saved ${bytes.length} bytes');
            return true;
          } catch (e) {
            debugPrint('[FontCache] Attempt error: $e');
            continue;
          }
        }
      }
      return false;
    } finally {
      client.close();
    }
  }

  /// Check if bytes start with valid font magic (TTF/OTF/TTC)
  static bool _isValidFontBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // TTF: 00 01 00 00
    if (bytes[0] == 0x00 && bytes[1] == 0x01 &&
        bytes[2] == 0x00 && bytes[3] == 0x00) return true;
    // OTF: OTTO
    if (bytes[0] == 0x4F && bytes[1] == 0x54 &&
        bytes[2] == 0x54 && bytes[3] == 0x4F) return true;
    // TTC: ttcf
    if (bytes[0] == 0x74 && bytes[1] == 0x74 &&
        bytes[2] == 0x63 && bytes[3] == 0x66) return true;
    return false;
  }

  /// Check if an existing file contains valid font data
  static bool _isValidFontFile(File file) {
    try {
      if (!file.existsSync() || file.lengthSync() < 1000) return false;
      final raf = file.openSync();
      final header = raf.readSync(4);
      raf.closeSync();
      return _isValidFontBytes(header);
    } catch (_) {
      return false;
    }
  }
}
