# Kế Hoạch Điều Khiển Prompter Từ Xa Qua Wi-Fi Nội Bộ

## Remote Control Architecture Plan

> **Mục tiêu**: Cho phép ekip điều khiển app Prompter từ thiết bị khác (laptop/tablet/phone) qua mạng Wi-Fi nội bộ, không cần Internet. Thiết bị hiển thị (display) chạy app Flutter làm máy chủ mini, thiết bị điều khiển chỉ cần mở trình duyệt web.

---

## I. ĐÁNH GIÁ KHẢ THI (Feasibility Assessment)

### ✅ KHẢ THI CAO — Đánh giá tổng thể: 9/10

| Tiêu chí | Đánh giá | Ghi chú |
|---|---|---|
| **Local HTTP Server trong Flutter** | ✅ Hoàn toàn khả thi | `dart:io` HttpServer chạy trên Android, iOS, Desktop |
| **WebSocket real-time** | ✅ Hoàn toàn khả thi | `dart:io` WebSocket native, không cần package ngoài |
| **mDNS Discovery** | ✅ Khả thi | Package `bonsoir` hỗ trợ Android, iOS, macOS, Windows, Linux |
| **Web Control Panel** | ✅ Khả thi | HTML/CSS/JS thuần, serve từ assets |
| **Tích hợp codebase hiện tại** | ✅ Rất thuận lợi | `PrompterSettings` đã centralized, dễ hook |
| **Không cần Internet** | ✅ Đúng thiết kế | Tất cả hoạt động trên LAN |
| **Bảo mật** | ⚠️ Chấp nhận được | Chỉ cùng mạng Wi-Fi mới truy cập được |
| **Đa nền tảng** | ✅ Tốt | Server chạy trên mọi platform Flutter hỗ trợ `dart:io` |

### Điểm mạnh của codebase hiện tại cho việc tích hợp:
1. **`PrompterSettings` (ChangeNotifier)** — Đã tập trung toàn bộ state, chỉ cần lắng nghe thay đổi và broadcast qua WebSocket
2. **Kiến trúc Provider** — Dễ inject thêm service mới
3. **Overlay sync pattern đã có** — `_onSettingsChanged()` trong `home_screen.dart` đã demo pattern sync settings realtime

---

## II. KIẾN TRÚC TỔNG THỂ (Architecture Design)

### Sơ đồ luồng hoạt động:

```
┌─────────────────────────────────────────────────────────────────┐
│                     MẠNG WI-FI NỘI BỘ (LAN)                    │
│                                                                  │
│  ┌──────────────────────┐         ┌──────────────────────────┐  │
│  │   THIẾT BỊ HIỂN THỊ  │         │  THIẾT BỊ ĐIỀU KHIỂN    │  │
│  │   (iPad/Phone/PC)     │         │  (Laptop/Phone/Tablet)   │  │
│  │                        │         │                          │  │
│  │  ┌──────────────────┐ │  mDNS   │  ┌────────────────────┐ │  │
│  │  │ Flutter App       │◄├─────────┤  │ Trình duyệt Web    │ │  │
│  │  │                   │ │Discovery│  │ (Chrome/Safari)     │ │  │
│  │  │ ┌──────────────┐ │ │         │  │                     │ │  │
│  │  │ │ HTTP Server   │◄├─────────►┤  │ GET /               │ │  │
│  │  │ │ :8080         │ │  HTTP    │  │ → Tải Web UI        │ │  │
│  │  │ └──────────────┘ │ │         │  │                     │ │  │
│  │  │ ┌──────────────┐ │ │         │  │ ┌─────────────────┐ │ │  │
│  │  │ │ WebSocket     │◄├─────────►┤  │ │ WebSocket Client│ │ │  │
│  │  │ │ /ws           │ │Realtime  │  │ │ (JavaScript)    │ │ │  │
│  │  │ └──────────────┘ │ │  Sync   │  │ └─────────────────┘ │ │  │
│  │  │ ┌──────────────┐ │ │         │  └────────────────────┘ │  │
│  │  │ │PrompterSettings│ │         │                          │  │
│  │  │ │ (State)       │ │         │  Có thể có nhiều client  │  │
│  │  │ └──────────────┘ │ │         │  kết nối cùng lúc       │  │
│  │  └──────────────────┘ │         └──────────────────────────┘  │
│  └──────────────────────┘                                        │
└─────────────────────────────────────────────────────────────────┘
```

### 3 Tầng công nghệ:

| Tầng | Công nghệ | Vai trò |
|---|---|---|
| **1. Discovery** | mDNS (Bonjour/NSD) | Tự động phát hiện thiết bị, không cần nhập IP |
| **2. Transport** | HTTP Server + WebSocket | Serve web UI + kênh truyền dữ liệu realtime |
| **3. Application** | JSON Protocol | Đồng bộ state, truyền lệnh điều khiển |

---

## III. LỰA CHỌN CÔNG NGHỆ (Technology Selection)

### Packages cần thêm:

| Package | Phiên bản | Mục đích | Kích thước |
|---|---|---|---|
| **`shelf`** | ^1.4.0 | HTTP request routing | Nhẹ (~50KB) |
| **`shelf_web_socket`** | ^2.0.0 | WebSocket upgrade handler | Nhẹ (~15KB) |
| **`shelf_static`** | ^1.1.0 | Serve static files (web UI) | Nhẹ (~20KB) |
| **`bonsoir`** | ^5.1.0 | mDNS cross-platform (Bonjour/NSD) | ~200KB |
| **`network_info_plus`** | ^6.1.0 | Lấy IP address hiện tại | Nhẹ (~30KB) |

### Tại sao chọn các package này?

**`shelf` thay vì `dart:io` HttpServer thuần:**
- Code sạch hơn với routing và middleware
- `shelf_web_socket` tích hợp sẵn WebSocket upgrade
- Dễ mở rộng (thêm authentication, logging)
- Vẫn dùng `dart:io` bên dưới

**`bonsoir` thay vì `multicast_dns` hoặc `nsd`:**
- Cross-platform: Android, iOS, macOS, Windows, Linux
- API thống nhất cho cả broadcast và discovery
- Maintained tốt, hỗ trợ Dart 3
- `multicast_dns` chỉ là Dart package, có vấn đề trên một số Android
- `nsd` chỉ hỗ trợ Android

**Không dùng `shelf_static` — Alternative:**
- Có thể embed HTML/JS trực tiếp dưới dạng Dart string constants
- Giảm 1 dependency, nhưng khó maintain web UI
- **Khuyến nghị**: Dùng `shelf_static` + assets folder cho clean separation

---

## IV. GIAO THỨC WEBSOCKET (Protocol Design)

### Định dạng message: JSON

#### Server → Client (Đồng bộ state)

```json
// Full state sync (khi client mới kết nối)
{
  "type": "full_sync",
  "data": {
    "text": "Văn bản nhắc chữ...",
    "scrollSpeed": 50.0,
    "fontFamily": "Roboto",
    "fontSize": 32.0,
    "isBold": true,
    "isItalic": false,
    "textColor": "#000000",
    "backgroundColor": "#00000000",
    "isPlaying": false,
    "mirrorHorizontal": false,
    "lineHeight": 1.5,
    "textAlign": "center",
    "opacity": 0.0,
    "paddingHorizontal": 20.0,
    "scrollMode": "vertical",
    "overlayPosition": "bottom",
    "overlayHeight": 150.0
  }
}

// Partial state update (khi có thay đổi)
{
  "type": "state_update",
  "data": {
    "scrollSpeed": 75.0
  }
}

// Server status
{
  "type": "status",
  "data": {
    "connectedClients": 2,
    "serverUptime": 3600,
    "displayMode": "fullscreen"
  }
}
```

#### Client → Server (Lệnh điều khiển)

```json
// Cập nhật văn bản
{
  "type": "update_text",
  "data": { "text": "Nội dung mới..." }
}

// Cập nhật settings
{
  "type": "update_settings",
  "data": {
    "scrollSpeed": 60.0,
    "fontSize": 36.0
  }
}

// Lệnh điều khiển
{
  "type": "command",
  "action": "play"        // play, pause, toggle, reset, scroll_up, scroll_down
}

// Request full sync
{
  "type": "request_sync"
}
```

### Cơ chế đồng bộ:

1. **Client kết nối** → Server gửi `full_sync` ngay lập tức
2. **Settings thay đổi trên server (từ app)** → Broadcast `state_update` tới tất cả clients
3. **Client gửi lệnh** → Server áp dụng → Broadcast `state_update` tới TẤT CẢ clients (bao gồm client gửi, để confirm)
4. **Client disconnect** → Server broadcast `status` update cho các client còn lại

---

## V. CẤU TRÚC THƯ MỤC MỚI (New File Structure)

```
lib/
├── main.dart                          (sửa nhỏ: khởi tạo server service)
├── models/
│   └── prompter_settings.dart         (thêm toJson/fromJson methods)
├── screens/
│   ├── home_screen.dart               (thêm UI bật/tắt server, hiển thị IP)
│   ├── overlay_prompter.dart          (không đổi)
│   └── prompter_screen.dart           (nhận lệnh từ WebSocket)
├── services/
│   ├── native_overlay_service.dart    (không đổi)
│   ├── overlay_service.dart           (không đổi)
│   ├── remote_server_service.dart     ★ MỚI — HTTP Server + WebSocket
│   └── mdns_service.dart              ★ MỚI — mDNS broadcast/discovery
├── widgets/
│   ├── color_picker_dialog.dart       (không đổi)
│   ├── text_preview.dart              (không đổi)
│   └── server_status_widget.dart      ★ MỚI — Widget hiển thị trạng thái server
└── web_controller/
    └── controller_page.dart           ★ MỚI — Dart string constants chứa HTML/JS

assets/
├── images/
└── web/                               ★ MỚI (tuỳ chọn — nếu dùng shelf_static)
    ├── index.html                     — Web control panel
    ├── style.css                      — Styling
    └── controller.js                  — WebSocket client logic
```

### Chi tiết từng file mới:

#### 1. `lib/services/remote_server_service.dart` (~200-250 dòng)

```dart
/// Quản lý Local HTTP Server + WebSocket
/// 
/// Responsibilities:
/// - Khởi tạo/dừng HTTP server trên port configurable
/// - Serve web control panel (HTML/CSS/JS)
/// - Quản lý WebSocket connections
/// - Lắng nghe PrompterSettings changes → broadcast to clients
/// - Nhận commands từ clients → cập nhật PrompterSettings
/// - Quản lý danh sách connected clients
class RemoteServerService extends ChangeNotifier {
  HttpServer? _server;
  final List<WebSocketChannel> _clients = [];
  final PrompterSettings _settings;
  bool _isRunning = false;
  int _port = 8080;
  String? _localIp;
  
  // Start server
  Future<void> startServer({int port = 8080}) async { ... }
  
  // Stop server
  Future<void> stopServer() async { ... }
  
  // Broadcast state to all clients
  void _broadcastState(Map<String, dynamic> data) { ... }
  
  // Handle incoming WebSocket message
  void _handleMessage(String message, WebSocketChannel sender) { ... }
  
  // Get local IP address
  Future<String?> _getLocalIpAddress() async { ... }
}
```

#### 2. `lib/services/mdns_service.dart` (~80-100 dòng)

```dart
/// Quản lý mDNS broadcast và discovery
///
/// Responsibilities:
/// - Broadcast service qua mDNS khi server bật
/// - Dừng broadcast khi server tắt
/// - Service type: _prompter._tcp
/// - Service name: "Prompter - {Device Name}"
class MdnsService {
  BonsoirBroadcast? _broadcast;
  
  Future<void> startBroadcast(int port) async { ... }
  Future<void> stopBroadcast() async { ... }
}
```

#### 3. `assets/web/index.html` (~300-400 dòng) — Web Control Panel

Giao diện web bao gồm:
- Header: Tên thiết bị + trạng thái kết nối (🟢/🔴)
- **Phần văn bản**: TextArea lớn để sửa text, nút Apply
- **Phần điều khiển chính**: Play/Pause, Reset, tốc độ cuộn (slider + giá trị)
- **Phần định dạng**: Font size, Bold/Italic, Căn lề
- **Phần nâng cao** (collapse): Font family, màu chữ, màu nền, mirror, opacity
- Footer: Số client đang kết nối, uptime

---

## VI. THAY ĐỔI TRÊN FILES HIỆN CÓ

### 1. `pubspec.yaml` — Thêm dependencies

```yaml
# Remote control
shelf: ^1.4.0
shelf_web_socket: ^2.0.0
bonsoir: ^5.1.0
network_info_plus: ^6.1.0
```

### 2. `lib/models/prompter_settings.dart` — Thêm serialization

```dart
// Thêm 2 methods:
Map<String, dynamic> toJson() {
  return {
    'text': text,
    'scrollSpeed': scrollSpeed,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'isBold': isBold,
    'isItalic': isItalic,
    'textColor': '#${textColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
    'backgroundColor': '#${backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
    'isPlaying': isPlaying,
    'mirrorHorizontal': mirrorHorizontal,
    'lineHeight': lineHeight,
    'textAlign': textAlign.name,
    'opacity': opacity,
    'paddingHorizontal': paddingHorizontal,
    'scrollMode': scrollMode.name,
    'overlayPosition': overlayPosition.name,
    'overlayHeight': overlayHeight,
  };
}

void applyFromJson(Map<String, dynamic> json) {
  // Apply từng field có trong json (partial update support)
  if (json.containsKey('text')) setText(json['text']);
  if (json.containsKey('scrollSpeed')) setScrollSpeed(json['scrollSpeed']);
  // ... tương tự cho các field khác
}
```

### 3. `lib/screens/home_screen.dart` — Thêm UI điều khiển server

```
Thêm vào Tab "Cài đặt":
┌──────────────────────────────────┐
│ 🌐 Điều khiển từ xa             │
│ ┌──────────────────────────────┐ │
│ │ [Bật Server]  Trạng thái: Tắt│ │
│ │                               │ │
│ │ Khi bật:                      │ │
│ │ IP: 192.168.1.45:8080        │ │
│ │ Thiết bị kết nối: 2          │ │
│ │ [Sao chép IP] [Hiện QR Code] │ │
│ └──────────────────────────────┘ │
└──────────────────────────────────┘
```

### 4. `android/app/src/main/AndroidManifest.xml` — Thêm permissions

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### 5. `ios/Runner/Info.plist` — Thêm mDNS permissions

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Ứng dụng cần truy cập mạng nội bộ để cho phép điều khiển từ xa</string>
<key>NSBonjourServices</key>
<array>
  <string>_prompter._tcp</string>
</array>
```

### 6. `lib/screens/prompter_screen.dart` — Nhận lệnh từ WebSocket

```dart
// Thêm listener: khi PrompterSettings thay đổi (từ WebSocket)
// → tự động reflect trên UI (đã có sẵn nhờ Provider pattern)
// → Không cần sửa nhiều, Provider đã handle rebuild
```

---

## VII. WEB CONTROL PANEL DESIGN (Chi tiết UI)

### Wireframe:

```
┌──────────────────────────────────────────────────────────────┐
│  🎤 Prompter Remote Control          🟢 Đã kết nối          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ Văn bản ──────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  [    TextArea - Nhập/sửa văn bản ở đây...         ]  │ │
│  │  [                                                   ]  │ │
│  │  [                                                   ]  │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ Điều khiển ───────────────────────────────────────────┐ │
│  │                                                         │ │
│  │    [ ⏮ Reset ]    [ ▶ Play / ⏸ Pause ]                │ │
│  │                                                         │ │
│  │    Tốc độ cuộn: ═══════●══════════  75 px/s            │ │
│  │                  10                200                   │ │
│  │                                                         │ │
│  │    Cỡ chữ:      ═══●═════════════  32 px               │ │
│  │                  12                120                   │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ▶ Định dạng nâng cao (bấm để mở)                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Font: [Roboto ▼]   [B] [I]                            │ │
│  │  Căn lề: [◀] [≡] [▶] [⊞]                              │ │
│  │  Màu chữ: [■ Đen ▼]    Màu nền: [■ Trắng ▼]          │ │
│  │  Mirror: [☐]   Opacity: ═══════●═══  70%               │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ──────────────────────────────────────────────────────────  │
│  2 thiết bị kết nối  •  Server uptime: 00:45:12            │
└──────────────────────────────────────────────────────────────┘
```

### Đặc điểm kỹ thuật Web UI:
- **Responsive**: Hoạt động tốt trên mobile browser và desktop browser
- **Vanilla JS**: Không framework (React/Vue), giảm kích thước
- **Offline-capable**: Toàn bộ HTML/CSS/JS serve từ server local, không CDN
- **Dark/Light theme**: Auto-detect từ trình duyệt
- **Touch-friendly**: Buttons và sliders đủ lớn cho thao tác trên mobile

---

## VIII. RỦI RO VÀ GIẢI PHÁP (Risks & Mitigations)

### Rủi ro kỹ thuật:

| # | Rủi ro | Mức độ | Giải pháp |
|---|---|---|---|
| 1 | **iOS background suspension** — Server bị dừng khi app vào background | Trung bình | App prompter luôn ở foreground khi hiển thị. Thêm warning cho user. iOS có `beginBackgroundTask` để xin thêm thời gian. |
| 2 | **Android battery optimization** — OS kill server process | Thấp | Đã có Foreground Service cho overlay. Server có thể share service này. |
| 3 | **Port conflict** — Port 8080 đã bị dùng | Thấp | Triển khai auto port selection: thử 8080 → 8081 → 8082... Hiển thị port thực tế trong UI. |
| 4 | **Wi-Fi AP Isolation** — Một số router chặn giao tiếp giữa devices | Trung bình | Hiển thị hướng dẫn troubleshoot. Cung cấp manual IP input fallback. |
| 5 | **mDNS không hoạt động** trên một số Android cũ | Thấp | Fallback: hiển thị IP + port rõ ràng, hỗ trợ QR code. |
| 6 | **Nhiều client sửa text cùng lúc** — Conflict | Thấp | Last-write-wins strategy. Hiển thị cảnh báo "Có người đang sửa". |
| 7 | **Kích thước web UI** lớn → load chậm | Rất thấp | HTML/CSS/JS thuần ~ 20-30KB. Qua LAN load < 50ms. |
| 8 | **WebSocket disconnect** do Wi-Fi không ổn định | Trung bình | Auto-reconnect trong JS client (exponential backoff). Hiển thị trạng thái kết nối rõ ràng. |

### Rủi ro bảo mật:

| # | Rủi ro | Giải pháp |
|---|---|---|
| 1 | Người lạ cùng Wi-Fi truy cập server | Thêm **PIN code** đơn giản (4 số) hiển thị trên app. Client phải nhập PIN khi kết nối lần đầu. |
| 2 | Injection qua WebSocket messages | Validate và sanitize tất cả JSON input trên server. Giới hạn kích thước message. |
| 3 | Denial of Service (quá nhiều kết nối) | Giới hạn max 5 WebSocket connections đồng thời. |

---

## IX. KẾ HOẠCH TRIỂN KHAI THEO PHASE

### Phase 1: Core Server + WebSocket (Nền tảng) ★ ƯU TIÊN CAO

**Objective**: Server chạy, WebSocket hoạt động, web UI cơ bản

| Task | File | Estimated Effort |
|---|---|---|
| Thêm dependencies vào pubspec.yaml | `pubspec.yaml` | Nhỏ |
| Thêm `toJson()` / `applyFromJson()` vào PrompterSettings | `prompter_settings.dart` | Nhỏ |
| Tạo `RemoteServerService` — HTTP server + WebSocket | `remote_server_service.dart` | Trung bình |
| Tạo Web Control Panel cơ bản (text + play/pause + speed) | `assets/web/` | Trung bình |
| Thêm UI bật/tắt server + hiển thị IP vào home_screen | `home_screen.dart` | Nhỏ |
| Thêm Android permissions | `AndroidManifest.xml` | Nhỏ |
| Test trên 2 thiết bị cùng Wi-Fi | — | Trung bình |

**Deliverable**: Ekip mở browser → gõ IP → thấy web UI → sửa text + điều khiển play/speed → iPad hiển thị realtime.

---

### Phase 2: mDNS Discovery (Tiện lợi)

| Task | File |
|---|---|
| Tạo `MdnsService` — broadcast + discovery | `mdns_service.dart` |
| Tích hợp mDNS vào server lifecycle | `remote_server_service.dart` |
| Thêm iOS permissions (NSLocalNetworkUsageDescription) | `Info.plist` |
| Thêm Android permissions (CHANGE_WIFI_MULTICAST_STATE) | `AndroidManifest.xml` |

**Deliverable**: Client có thể tìm server tự động thay vì gõ IP thủ công.

---

### Phase 3: Web UI Hoàn Chỉnh (Polish)

| Task | File |
|---|---|
| Thêm font controls vào web UI | `assets/web/` |
| Thêm color pickers vào web UI | `assets/web/` |
| Thêm mirror, opacity, alignment controls | `assets/web/` |
| Responsive design cho mobile browser | `assets/web/style.css` |
| Dark/Light theme | `assets/web/style.css` |
| Hiển thị text preview trên web UI | `assets/web/` |

**Deliverable**: Web UI có đầy đủ chức năng như app.

---

### Phase 4: Security & UX (Hardening)

| Task | File |
|---|---|
| PIN code authentication | `remote_server_service.dart` + web UI |
| QR code hiển thị connection info | `home_screen.dart` |
| Auto-reconnect trong web client | `assets/web/controller.js` |
| Connection status indicators | Both app + web |
| Max client limit (5) | `remote_server_service.dart` |
| Input sanitization/validation | `remote_server_service.dart` |

**Deliverable**: Production-ready, an toàn, UX mượt mà.

---

### Phase 5: Advanced Features (Mở rộng — Tùy chọn)

| Task | Mô tả |
|---|---|
| **Multi-device sync** | Nhiều iPad cùng hiển thị, 1 bộ điều khiển |
| **Cue points** | Đánh dấu vị trí trong text, nhảy tới cue |
| **Script management** | Upload/lưu nhiều scripts, chuyển nhanh |
| **Timer display** | Hiển thị thời gian đã live |
| **Flutter client app** | App điều khiển native (thay vì web) cho trải nghiệm tốt hơn |

---

## X. MẪU CODE THAM KHẢO (Code Sketches)

### 1. RemoteServerService — Khung cơ bản

```dart
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RemoteServerService extends ChangeNotifier {
  HttpServer? _server;
  final Set<WebSocketChannel> _clients = {};
  final PrompterSettings _settings;
  bool _isRunning = false;
  int _port = 8080;
  String? _localIp;

  RemoteServerService(this._settings) {
    _settings.addListener(_onSettingsChanged);
  }

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get localIp => _localIp;
  int get clientCount => _clients.length;
  String get connectionUrl => 'http://$_localIp:$_port';

  Future<void> startServer({int port = 8080}) async {
    if (_isRunning) return;
    
    _localIp = await _getLocalIpAddress();
    
    // WebSocket handler
    final wsHandler = webSocketHandler((WebSocketChannel ws) {
      _clients.add(ws);
      notifyListeners();
      
      // Send full state on connect
      ws.sink.add(jsonEncode({
        'type': 'full_sync',
        'data': _settings.toJson(),
      }));
      
      // Listen for messages
      ws.stream.listen(
        (message) => _handleMessage(message as String, ws),
        onDone: () {
          _clients.remove(ws);
          notifyListeners();
        },
      );
    });

    // HTTP handler (serve web UI)
    final staticHandler = (shelf.Request request) {
      // Return index.html for root
      if (request.url.path.isEmpty || request.url.path == '/') {
        return shelf.Response.ok(
          _getIndexHtml(),
          headers: {'Content-Type': 'text/html; charset=utf-8'},
        );
      }
      return shelf.Response.notFound('Not found');
    };

    // Route: /ws → WebSocket, everything else → static files
    final handler = (shelf.Request request) {
      if (request.url.path == 'ws') {
        return wsHandler(request);
      }
      return staticHandler(request);
    };

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _port = _server!.port;
    _isRunning = true;
    notifyListeners();
  }

  void _onSettingsChanged() {
    _broadcast({
      'type': 'state_update',
      'data': _settings.toJson(),
    });
  }

  void _broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final client in _clients.toList()) {
      client.sink.add(encoded);
    }
  }

  void _handleMessage(String raw, WebSocketChannel sender) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'update_settings':
        _settings.applyFromJson(msg['data'] as Map<String, dynamic>);
        break;
      case 'update_text':
        _settings.setText(msg['data']['text'] as String);
        break;
      case 'command':
        _handleCommand(msg['action'] as String);
        break;
      case 'request_sync':
        sender.sink.add(jsonEncode({
          'type': 'full_sync',
          'data': _settings.toJson(),
        }));
        break;
    }
  }

  void _handleCommand(String action) {
    switch (action) {
      case 'play':
        _settings.setPlaying(true);
        break;
      case 'pause':
        _settings.setPlaying(false);
        break;
      case 'toggle':
        _settings.togglePlaying();
        break;
      case 'reset':
        _settings.setPlaying(false);
        // Signal reset scroll position (cần thêm mechanism)
        break;
    }
  }

  Future<String?> _getLocalIpAddress() async {
    // Sử dụng network_info_plus hoặc dart:io
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }

  Future<void> stopServer() async {
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    _isRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    stopServer();
    super.dispose();
  }
}
```

### 2. Web Controller — JavaScript WebSocket Client (Sketch)

```javascript
// controller.js
const ws = new WebSocket(`ws://${window.location.host}/ws`);
let state = {};

ws.onopen = () => {
  document.getElementById('status').textContent = '🟢 Đã kết nối';
};

ws.onclose = () => {
  document.getElementById('status').textContent = '🔴 Mất kết nối';
  // Auto-reconnect sau 2 giây
  setTimeout(() => location.reload(), 2000);
};

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === 'full_sync' || msg.type === 'state_update') {
    state = { ...state, ...msg.data };
    updateUI(state);
  }
};

function sendCommand(action) {
  ws.send(JSON.stringify({ type: 'command', action }));
}

function updateSettings(data) {
  ws.send(JSON.stringify({ type: 'update_settings', data }));
}

function updateText(text) {
  ws.send(JSON.stringify({ type: 'update_text', data: { text } }));
}
```

---

## XI. PLATFORM-SPECIFIC CONSIDERATIONS

### Android
- ✅ `dart:io` HttpServer — Supported
- ✅ WebSocket — Supported
- ✅ `bonsoir` mDNS — Uses Android NSD APIs
- ⚠️ Cần thêm `INTERNET` permission vào **main** manifest (hiện chỉ có ở debug/profile)
- ⚠️ Cần `CHANGE_WIFI_MULTICAST_STATE` cho mDNS
- ✅ Foreground Service đã có → Server ổn định khi app ở background

### iOS
- ✅ `dart:io` HttpServer — Supported
- ✅ WebSocket — Supported
- ✅ `bonsoir` mDNS — Uses Apple Bonjour
- ⚠️ Phải khai báo `NSLocalNetworkUsageDescription` và `NSBonjourServices`
- ⚠️ App bị suspend khi vào background → Server sẽ dừng (chấp nhận được vì prompter luôn foreground)
- ⚠️ iOS 14+ yêu cầu Local Network permission dialog

### Windows / macOS / Linux (Desktop)
- ✅ Tất cả đều hỗ trợ tốt `dart:io` HttpServer
- ✅ `bonsoir` hỗ trợ Windows, macOS, Linux
- ✅ Không có background restrictions như mobile
- ✅ Desktop là platform lý tưởng nhất cho server role

### Web (Flutter Web)
- ❌ **KHÔNG hỗ trợ** — `dart:io` không available trên Flutter Web
- Giải pháp: Nếu cần, chuyển sang WebRTC hoặc external server
- **Khuyến nghị**: Không cần hỗ trợ Flutter Web cho tính năng server

---

## XII. SO SÁNH VỚI CÁC APP THƯƠNG MẠI

| Tính năng | dvPrompter | Prompter Our App (Planned) |
|---|---|---|
| Local Server | ✅ | ✅ Phase 1 |
| WebSocket Realtime | ✅ | ✅ Phase 1 |
| Browser-based Remote | ✅ | ✅ Phase 1 |
| mDNS Discovery | ✅ | ✅ Phase 2 |
| PIN Security | ✅ | ✅ Phase 4 |
| QR Code Connect | ✅ | ✅ Phase 4 |
| Overlay Mode | ❓ | ✅ Đã có |
| Movie Credits Mode | ❌ | ✅ Đã có |
| Mirror/Flip | ✅ | ✅ Đã có |
| Multi-script | ✅ | Phase 5 (tùy chọn) |
| Cue Points | ✅ | Phase 5 (tùy chọn) |

---

## XIII. KẾT LUẬN

### Tóm tắt:

Giải pháp **Local Server + WebSocket + mDNS** là **hoàn toàn khả thi** với codebase Prompter hiện tại. Các lý do chính:

1. **Dart/Flutter native support**: `dart:io` cung cấp HttpServer và WebSocket sẵn, không cần công nghệ ngoài
2. **Kiến trúc sẵn sàng**: `PrompterSettings` centralized state + Provider pattern = dễ hook realtime sync
3. **Ecosystem package tốt**: `shelf`, `bonsoir` đều mature và cross-platform
4. **Zero Internet dependency**: Toàn bộ chạy trên LAN, đúng theo yêu cầu
5. **Progressive implementation**: Chia 5 phases, Phase 1 đã có giá trị sử dụng ngay

### Khuyến nghị:
- **Bắt đầu từ Phase 1** — Đã đủ dùng cho 90% use cases
- **Phase 2 (mDNS)** nên triển khai sớm — UX cải thiện rõ rệt
- **Phase 3-4** triển khai khi Phase 1-2 ổn định
- **Phase 5** chỉ khi có nhu cầu thực tế

### Lệnh tiếp theo (khi sẵn sàng implement):
```
"Hãy implement Phase 1: Core Server + WebSocket"
```

---

*Document created: 2026-03-07*
*Codebase version: Prompter v1.1.1+3*
*Flutter SDK: ^3.10.4*
