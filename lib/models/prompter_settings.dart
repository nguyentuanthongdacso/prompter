import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vị trí dải overlay trên màn hình
enum OverlayStripPosition { top, center, bottom }

// Kiểu cuộn chữ
enum ScrollMode { vertical, movieCredits }

class PrompterSettings extends ChangeNotifier {
  String _text = 'Nhập văn bản của bạn ở đây...\n\nĐây là ứng dụng nhắc chữ (Prompter) giúp bạn đọc văn bản một cách dễ dàng.';
  double _scrollSpeed = 50.0; // pixels per second
  String _fontFamily = 'Roboto';
  double _fontSize = 32.0;
  bool _isBold = true;
  bool _isItalic = false;
  Color _textColor = Colors.black; // Black text for camera overlay
  Color _backgroundColor = Colors.transparent; // Transparent background
  bool _isPlaying = false;
  bool _mirrorHorizontal = false;
  double _lineHeight = 1.5;
  TextAlign _textAlign = TextAlign.center;
  double _opacity = 0.0; // Fully transparent
  double _paddingHorizontal = 20.0;
  OverlayStripPosition _overlayPosition = OverlayStripPosition.bottom;
  double _overlayHeight = 150.0; // Height in pixels for overlay strip
  ScrollMode _scrollMode = ScrollMode.vertical;

  // Getters
  String get text => _text;
  double get scrollSpeed => _scrollSpeed;
  String get fontFamily => _fontFamily;
  double get fontSize => _fontSize;
  bool get isBold => _isBold;
  bool get isItalic => _isItalic;
  Color get textColor => _textColor;
  Color get backgroundColor => _backgroundColor;
  bool get isPlaying => _isPlaying;
  bool get mirrorHorizontal => _mirrorHorizontal;
  double get lineHeight => _lineHeight;
  TextAlign get textAlign => _textAlign;
  double get opacity => _opacity;
  double get paddingHorizontal => _paddingHorizontal;
  OverlayStripPosition get overlayPosition => _overlayPosition;
  double get overlayHeight => _overlayHeight;
  ScrollMode get scrollMode => _scrollMode;

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _text = prefs.getString('text') ?? _text;
    _scrollSpeed = prefs.getDouble('scrollSpeed') ?? _scrollSpeed;
    _fontFamily = prefs.getString('fontFamily') ?? _fontFamily;
    _fontSize = prefs.getDouble('fontSize') ?? _fontSize;
    _isBold = prefs.getBool('isBold') ?? _isBold;
    _isItalic = prefs.getBool('isItalic') ?? _isItalic;
    _textColor = Color(prefs.getInt('textColor') ?? _textColor.toARGB32());
    _backgroundColor = Color(prefs.getInt('backgroundColor') ?? _backgroundColor.toARGB32());
    _mirrorHorizontal = prefs.getBool('mirrorHorizontal') ?? _mirrorHorizontal;
    _lineHeight = prefs.getDouble('lineHeight') ?? _lineHeight;
    final alignIndex = prefs.getInt('textAlign') ?? _textAlign.index;
    _textAlign = TextAlign.values[alignIndex.clamp(0, TextAlign.values.length - 1)];
    _opacity = prefs.getDouble('opacity') ?? _opacity;
    _paddingHorizontal = prefs.getDouble('paddingHorizontal') ?? _paddingHorizontal;
    final posIndex = prefs.getInt('overlayPosition') ?? _overlayPosition.index;
    _overlayPosition = OverlayStripPosition.values[posIndex.clamp(0, OverlayStripPosition.values.length - 1)];
    _overlayHeight = prefs.getDouble('overlayHeight') ?? _overlayHeight;
    final modeIndex = prefs.getInt('scrollMode') ?? _scrollMode.index;
    _scrollMode = ScrollMode.values[modeIndex.clamp(0, ScrollMode.values.length - 1)];
    notifyListeners();
  }

  // Save all settings to SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('text', _text);
    await prefs.setDouble('scrollSpeed', _scrollSpeed);
    await prefs.setString('fontFamily', _fontFamily);
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setBool('isBold', _isBold);
    await prefs.setBool('isItalic', _isItalic);
    await prefs.setInt('textColor', _textColor.toARGB32());
    await prefs.setInt('backgroundColor', _backgroundColor.toARGB32());
    await prefs.setBool('mirrorHorizontal', _mirrorHorizontal);
    await prefs.setDouble('lineHeight', _lineHeight);
    await prefs.setInt('textAlign', _textAlign.index);
    await prefs.setDouble('opacity', _opacity);
    await prefs.setDouble('paddingHorizontal', _paddingHorizontal);
    await prefs.setInt('overlayPosition', _overlayPosition.index);
    await prefs.setDouble('overlayHeight', _overlayHeight);
    await prefs.setInt('scrollMode', _scrollMode.index);
  }

  // Setters with notifyListeners
  void setText(String value) {
    _text = value;
    notifyListeners();
    _save();
  }

  void setScrollSpeed(double value) {
    _scrollSpeed = value.clamp(10.0, 200.0);
    notifyListeners();
    _save();
  }

  void setFontFamily(String value) {
    _fontFamily = value;
    notifyListeners();
    _save();
  }

  void setFontSize(double value) {
    _fontSize = value.clamp(12.0, 120.0);
    notifyListeners();
    _save();
  }

  void toggleBold() {
    _isBold = !_isBold;
    notifyListeners();
    _save();
  }

  void toggleItalic() {
    _isItalic = !_isItalic;
    notifyListeners();
    _save();
  }

  void setTextColor(Color value) {
    _textColor = value;
    notifyListeners();
    _save();
  }

  void setBackgroundColor(Color value) {
    _backgroundColor = value;
    notifyListeners();
    _save();
  }

  void togglePlaying() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void setPlaying(bool value) {
    _isPlaying = value;
    notifyListeners();
  }

  void toggleMirror() {
    _mirrorHorizontal = !_mirrorHorizontal;
    notifyListeners();
    _save();
  }

  void setLineHeight(double value) {
    _lineHeight = value.clamp(1.0, 3.0);
    notifyListeners();
    _save();
  }

  void setTextAlign(TextAlign value) {
    _textAlign = value;
    notifyListeners();
    _save();
  }

  void setOpacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
    notifyListeners();
    _save();
  }

  void setPaddingHorizontal(double value) {
    _paddingHorizontal = value.clamp(0.0, 100.0);
    notifyListeners();
    _save();
  }

  void setOverlayPosition(OverlayStripPosition value) {
    _overlayPosition = value;
    notifyListeners();
    _save();
  }

  void setOverlayHeight(double value) {
    _overlayHeight = value.clamp(80.0, 700.0);
    notifyListeners();
    _save();
  }

  void setScrollMode(ScrollMode value) {
    _scrollMode = value;
    notifyListeners();
    _save();
  }

  // System fonts that don't need Google Fonts
  static const _systemFonts = ['Arial', 'Times New Roman'];

  // Get TextStyle based on current settings
  TextStyle getTextStyle() {
    final baseStyle = TextStyle(
      fontSize: _fontSize,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      color: _textColor,
      height: _lineHeight,
    );

    if (_systemFonts.contains(_fontFamily)) {
      return baseStyle.copyWith(fontFamily: _fontFamily);
    }

    try {
      return GoogleFonts.getFont(
        _fontFamily,
        fontSize: _fontSize,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        color: _textColor,
        height: _lineHeight,
      );
    } catch (e) {
      return baseStyle;
    }
  }

  // Available fonts
  static List<String> get availableFonts => [
    'Arial',
    'Times New Roman',
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Oswald',
    'Raleway',
    'Poppins',
    'Playfair Display',
    'Merriweather',
    'Ubuntu',
    'Nunito',
    'Noto Sans',
  ];

  // Preset colors with names
  static List<Map<String, dynamic>> get presetColorsWithNames => [
    {'name': 'Trắng', 'color': Colors.white},
    {'name': 'Đen', 'color': Colors.black},
    {'name': 'Đỏ', 'color': Colors.red},
    {'name': 'Xanh lá', 'color': Colors.green},
    {'name': 'Xanh dương', 'color': Colors.blue},
    {'name': 'Vàng', 'color': Colors.yellow},
    {'name': 'Cam', 'color': Colors.orange},
    {'name': 'Tím', 'color': Colors.purple},
    {'name': 'Hồng', 'color': Colors.pink},
    {'name': 'Xám', 'color': Colors.grey},
  ];

  static List<Color> get presetColors => 
    presetColorsWithNames.map((e) => e['color'] as Color).toList();

  // Serialize all settings to JSON for WebSocket sync
  Map<String, dynamic> toJson() {
    return {
      'text': _text,
      'scrollSpeed': _scrollSpeed,
      'fontFamily': _fontFamily,
      'fontSize': _fontSize,
      'isBold': _isBold,
      'isItalic': _isItalic,
      'textColor': '#${_textColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'backgroundColor': '#${_backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'isPlaying': _isPlaying,
      'mirrorHorizontal': _mirrorHorizontal,
      'lineHeight': _lineHeight,
      'textAlign': _textAlign.name,
      'opacity': _opacity,
      'paddingHorizontal': _paddingHorizontal,
      'scrollMode': _scrollMode.name,
      'overlayPosition': _overlayPosition.name,
      'overlayHeight': _overlayHeight,
    };
  }

  // Apply partial or full settings from JSON (from WebSocket remote control)
  void applyFromJson(Map<String, dynamic> json) {
    // Apply all changes directly to fields, then notify once to avoid
    // multiple overlay rebuilds per remote update.
    bool changed = false;

    if (json.containsKey('text') && json['text'] as String != _text) {
      _text = json['text'] as String;
      changed = true;
    }
    if (json.containsKey('scrollSpeed')) {
      final v = (json['scrollSpeed'] as num).toDouble().clamp(10.0, 200.0);
      if (v != _scrollSpeed) { _scrollSpeed = v; changed = true; }
    }
    if (json.containsKey('fontFamily') && json['fontFamily'] as String != _fontFamily) {
      _fontFamily = json['fontFamily'] as String;
      changed = true;
    }
    if (json.containsKey('fontSize')) {
      final v = (json['fontSize'] as num).toDouble().clamp(12.0, 120.0);
      if (v != _fontSize) { _fontSize = v; changed = true; }
    }
    if (json.containsKey('isBold') && (json['isBold'] as bool) != _isBold) {
      _isBold = json['isBold'] as bool;
      changed = true;
    }
    if (json.containsKey('isItalic') && (json['isItalic'] as bool) != _isItalic) {
      _isItalic = json['isItalic'] as bool;
      changed = true;
    }
    if (json.containsKey('textColor')) {
      final c = _parseColor(json['textColor'] as String);
      if (c != _textColor) { _textColor = c; changed = true; }
    }
    if (json.containsKey('backgroundColor')) {
      final c = _parseColor(json['backgroundColor'] as String);
      if (c != _backgroundColor) { _backgroundColor = c; changed = true; }
    }
    if (json.containsKey('mirrorHorizontal') && (json['mirrorHorizontal'] as bool) != _mirrorHorizontal) {
      _mirrorHorizontal = json['mirrorHorizontal'] as bool;
      changed = true;
    }
    if (json.containsKey('lineHeight')) {
      final v = (json['lineHeight'] as num).toDouble().clamp(1.0, 3.0);
      if (v != _lineHeight) { _lineHeight = v; changed = true; }
    }
    if (json.containsKey('textAlign')) {
      final align = TextAlign.values.firstWhere(
        (e) => e.name == json['textAlign'],
        orElse: () => TextAlign.center,
      );
      if (align != _textAlign) { _textAlign = align; changed = true; }
    }
    if (json.containsKey('opacity')) {
      final v = (json['opacity'] as num).toDouble().clamp(0.0, 1.0);
      if (v != _opacity) { _opacity = v; changed = true; }
    }
    if (json.containsKey('paddingHorizontal')) {
      final v = (json['paddingHorizontal'] as num).toDouble().clamp(0.0, 100.0);
      if (v != _paddingHorizontal) { _paddingHorizontal = v; changed = true; }
    }
    if (json.containsKey('scrollMode')) {
      final mode = ScrollMode.values.firstWhere(
        (e) => e.name == json['scrollMode'],
        orElse: () => ScrollMode.vertical,
      );
      if (mode != _scrollMode) { _scrollMode = mode; changed = true; }
    }
    if (json.containsKey('overlayPosition')) {
      final pos = OverlayStripPosition.values.firstWhere(
        (e) => e.name == json['overlayPosition'],
        orElse: () => OverlayStripPosition.bottom,
      );
      if (pos != _overlayPosition) { _overlayPosition = pos; changed = true; }
    }
    if (json.containsKey('overlayHeight')) {
      final v = (json['overlayHeight'] as num).toDouble().clamp(80.0, 700.0);
      if (v != _overlayHeight) { _overlayHeight = v; changed = true; }
    }

    if (changed) {
      notifyListeners();
      _save();
    }
  }

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.black;
    if (cleaned.length == 6) return Color(0xFF000000 | value);
    return Color(value);
  }
}
