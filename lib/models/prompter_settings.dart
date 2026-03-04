import 'package:flutter/material.dart';

// Vị trí dải overlay trên màn hình
enum OverlayStripPosition { top, center, bottom }

class PrompterSettings extends ChangeNotifier {
  String _text = 'Nhập văn bản của bạn ở đây...\n\nĐây là ứng dụng nhắc chữ (Prompter) giúp bạn đọc văn bản một cách dễ dàng.';
  double _scrollSpeed = 50.0; // pixels per second
  String _fontFamily = 'Roboto';
  double _fontSize = 32.0;
  bool _isBold = false;
  bool _isItalic = false;
  Color _textColor = Colors.white;
  Color _backgroundColor = const Color.fromRGBO(0, 0, 0, 0.8);
  bool _isPlaying = false;
  bool _mirrorHorizontal = false;
  double _lineHeight = 1.5;
  TextAlign _textAlign = TextAlign.center;
  double _opacity = 0.9;
  double _paddingHorizontal = 20.0;
  OverlayStripPosition _overlayPosition = OverlayStripPosition.bottom;
  double _overlayHeight = 150.0; // Height in pixels for overlay strip

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

  // Setters with notifyListeners
  void setText(String value) {
    _text = value;
    notifyListeners();
  }

  void setScrollSpeed(double value) {
    _scrollSpeed = value.clamp(10.0, 200.0);
    notifyListeners();
  }

  void setFontFamily(String value) {
    _fontFamily = value;
    notifyListeners();
  }

  void setFontSize(double value) {
    _fontSize = value.clamp(12.0, 120.0);
    notifyListeners();
  }

  void toggleBold() {
    _isBold = !_isBold;
    notifyListeners();
  }

  void toggleItalic() {
    _isItalic = !_isItalic;
    notifyListeners();
  }

  void setTextColor(Color value) {
    _textColor = value;
    notifyListeners();
  }

  void setBackgroundColor(Color value) {
    _backgroundColor = value;
    notifyListeners();
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
  }

  void setLineHeight(double value) {
    _lineHeight = value.clamp(1.0, 3.0);
    notifyListeners();
  }

  void setTextAlign(TextAlign value) {
    _textAlign = value;
    notifyListeners();
  }

  void setOpacity(double value) {
    _opacity = value.clamp(0.1, 1.0);
    notifyListeners();
  }

  void setPaddingHorizontal(double value) {
    _paddingHorizontal = value.clamp(0.0, 100.0);
    notifyListeners();
  }

  void setOverlayPosition(OverlayStripPosition value) {
    _overlayPosition = value;
    notifyListeners();
  }

  void setOverlayHeight(double value) {
    _overlayHeight = value.clamp(80.0, 400.0);
    notifyListeners();
  }

  // Get TextStyle based on current settings
  TextStyle getTextStyle() {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      color: _textColor,
      height: _lineHeight,
    );
  }

  // Available fonts
  static List<String> get availableFonts => [
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
}
