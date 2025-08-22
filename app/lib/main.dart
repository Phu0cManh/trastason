import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DeviceSelectScreen(),
    theme: ThemeData.dark(),
  ));
}

class ChannelData {
  final String name;
  double voltage;
  double current;
  double power;
  List<FlSpot> vHistory = [];
  List<FlSpot> aHistory = [];
  List<FlSpot> wHistory = [];
  double t = 0;

  ChannelData(this.name, {this.voltage = 0, this.current = 0, this.power = 0});
}

class DeviceSelectScreen extends StatefulWidget {
  @override
  State<DeviceSelectScreen> createState() => _DeviceSelectScreenState();
}

class _DeviceSelectScreenState extends State<DeviceSelectScreen> {
  List<ScanResult> devices = [];
  bool scanning = false;

  // --- Bluetooth state ---
  bool btOn = false;
  StreamSubscription<BluetoothAdapterState>? _btSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void initState() {
    super.initState();

    // Lắng nghe trạng thái Bluetooth
    _btSub = FlutterBluePlus.adapterState.listen((s) {
      final wasOff = !btOn;
      btOn = (s == BluetoothAdapterState.on);
      setState(() {});
      // BT vừa bật -> tự động quét
      if (wasOff && btOn) {
        _startScan();
      }
    });

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _startScan();
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _enableBluetooth() async {
    try {
      await FlutterBluePlus.turnOn(); // Android: mở dialog bật BT
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể bật Bluetooth tự động. Hãy bật Bluetooth trong Cài đặt.')),
      );
    }
  }

  void _startScan() async {
    // Kiểm tra BT đã bật chưa
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() {
        scanning = false;
        devices.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth đang tắt. Hãy bật Bluetooth trước khi quét.')),
      );
      return;
    }

    // Xin quyền
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
    ].request();

    setState(() {
      devices.clear();
      scanning = true;
    });

    // Hủy listener cũ (nếu có) để tránh lặp
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();

    // Bắt đầu quét
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) =>
          (r.device.platformName.isNotEmpty) ||
          (r.advertisementData.serviceUuids.isNotEmpty)).toList();
      setState(() {
        devices = filtered;
      });
      for (var r in filtered) {
        // ignore: avoid_print
        print('Found BLE: ${r.device.platformName} - ${r.device.remoteId.str}');
      }
    });

    // Dừng quét sau timeout (phòng trường hợp)
    Future.delayed(Duration(seconds: 5)).then((_) async {
      if (mounted) {
        setState(() => scanning = false);
      }
      await FlutterBluePlus.stopScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chọn thiết bị BLE')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Banner nhắc bật Bluetooth (trên–giữa)
          if (!btOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth_disabled, size: 64, color: Colors.redAccent),
                    SizedBox(height: 12),
                    Text(
                      'Bluetooth đang tắt',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Hãy bật Bluetooth để bắt đầu quét thiết bị.',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _enableBluetooth,
                      icon: Icon(Icons.power_settings_new),
                      label: Text('Bật Bluetooth'),
                    ),
                  ],
                ),
              ),
            ),

          if (scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedRotation(
                      turns: scanning ? 1 : 0,
                      duration: Duration(seconds: 2),
                      child: Icon(Icons.bluetooth_searching,
                          size: 64, color: Colors.tealAccent),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Đang quét thiết bị Bluetooth...',
                      style: TextStyle(fontSize: 16, color: Colors.tealAccent),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Đã tìm thấy: ${devices.length}',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            ),

          if (!scanning && devices.isEmpty && btOn)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Không tìm thấy thiết bị nào!',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          if (devices.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final r = devices[index];
                  final deviceName = (r.device.platformName.isNotEmpty)
                      ? r.device.platformName
                      : "Không tên";
                  return ListTile(
                    leading: Icon(Icons.bluetooth, color: Colors.tealAccent),
                    title: Text(deviceName),
                    subtitle: Text(r.device.remoteId.str),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomeScreen(device: r.device),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, top: 8),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: (!btOn || scanning) ? null : _startScan,
                icon: Icon(Icons.refresh),
                label: Text('Quét lại'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final BluetoothDevice device;
  const HomeScreen({required this.device});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<ChannelData> channels = [
    ChannelData('C1'),
    ChannelData('C2'),
    ChannelData('C3'),
    ChannelData('C4'),
    ChannelData('USB-A'),
  ];

  BluetoothCharacteristic? notifyChar;

  List<ChargeSession> history = [];
  DateTime? sessionStart;
  List<FlSpot> sessionV = [];
  List<FlSpot> sessionA = [];
  List<FlSpot> sessionW = [];
  bool charging = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _loadHistoryOnStart();
    _connectAndDiscover();
  }

  void _loadHistoryOnStart() async {
    history = await loadHistory();
    setState(() {});
  }

  void _connectAndDiscover() async {
    await widget.device.connect();
    List<BluetoothService> services = await widget.device.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == "12345678-1234-1234-1234-1234567890ab") {
        for (var c in service.characteristics) {
          if (c.uuid.toString().toLowerCase() == "abcd1234-abcd-1234-abcd-1234567890ab") {
            notifyChar = c;
            await notifyChar!.setNotifyValue(true);
            notifyChar!.onValueReceived.listen(_onDataReceived);
            break;
          }
        }
      }
    }
  }

  void _onDataReceived(List<int> value) {
    final message = String.fromCharCodes(value);
    final lines = message.split('\n');
    double v = 0, a = 0, w = 0;
    for (var line in lines) {
      for (var ch in channels) {
        if (line.startsWith(ch.name)) {
          final parts = line.split(':');
          if (parts.length > 1) {
            final values = parts[1].split(',');
            if (values.length == 3) {
              v = double.tryParse(values[0].replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
              a = double.tryParse(values[1].replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
              w = double.tryParse(values[2].replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
              setState(() {
                ch.voltage = v;
                ch.current = a;
                ch.power = w;
                ch.t += 0.5;
                if (ch.vHistory.length > 100) {
                  ch.vHistory.removeAt(0);
                  ch.aHistory.removeAt(0);
                  ch.wHistory.removeAt(0);
                }
                ch.vHistory.add(FlSpot(ch.t, v));
                ch.aHistory.add(FlSpot(ch.t, a));
                ch.wHistory.add(FlSpot(ch.t, w));
              });
            }
          }
        }
      }
    }

    // --- Lưu lịch sử phiên sạc ---
    final mainCh = channels[0];
    bool nowCharging = mainCh.voltage > 0 && mainCh.current > 0;
    if (nowCharging && !charging) {
      charging = true;
      sessionStart = DateTime.now();
      sessionV = [];
      sessionA = [];
      sessionW = [];
    }
    if (nowCharging) {
      double t = sessionV.isNotEmpty ? sessionV.last.x + 0.5 : 0;
      sessionV.add(FlSpot(t, mainCh.voltage));
      sessionA.add(FlSpot(t, mainCh.current));
      sessionW.add(FlSpot(t, mainCh.power));
    }
    if (!nowCharging && charging) {
      charging = false;
      if (sessionStart != null && sessionV.length > 2) {
        history.add(ChargeSession(
          start: sessionStart!,
          end: DateTime.now(),
          vHistory: List<FlSpot>.from(sessionV),
          aHistory: List<FlSpot>.from(sessionA),
          wHistory: List<FlSpot>.from(sessionW),
        ));
        saveHistory(history);
      }
      sessionStart = null;
      sessionV = [];
      sessionA = [];
      sessionW = [];
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2 hàng, 3 cột, màn hình dọc
    return Scaffold(
      appBar: AppBar(
        title: Text('Power Monitor'),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            tooltip: 'Lịch sử sạc',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(history: history),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.count(
          crossAxisCount: 2,
          children: [
            ...channels.map((ch) => GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChartScreen(channel: ch),
                      ),
                    );
                  },
                  child: Card(
                    color: Colors.blueGrey.shade900,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.tealAccent, width: 2)),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            ch.name,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.tealAccent),
                          ),
                          SizedBox(height: 12),
                          Text('${ch.voltage.toStringAsFixed(2)} V',
                              style: TextStyle(fontSize: 18)),
                          Text('${ch.current.toStringAsFixed(2)} A',
                              style: TextStyle(fontSize: 18)),
                          Text('${ch.power.toStringAsFixed(2)} W',
                              style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                )),
            // Ô thứ 6: logo hoặc tên
            Card(
              color: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.tealAccent, width: 2)),
              elevation: 8,
              child: Center(
                child: Text(
                  'Nhiệt Độ',
                  style: TextStyle(
                      fontSize: 20,
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartScreen extends StatefulWidget {
  final ChannelData channel;
  const ChartScreen({required this.channel});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final String _unit = 's';
  final double _unitDiv = 1.0;
  DateTime? startTime;

  @override
  void initState() {
    super.initState();
    if (widget.channel.vHistory.isNotEmpty) {
      double totalSeconds = widget.channel.vHistory.last.x;
      startTime = DateTime.now().subtract(Duration(milliseconds: (totalSeconds * 1000).toInt()));
    } else {
      startTime = DateTime.now();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRealtimeUpdate();
    });
  }

  bool _running = true;

  void _startRealtimeUpdate() async {
    while (_running) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _running = false;
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final vList = widget.channel.vHistory;
    final aList = widget.channel.aHistory;
    final wList = widget.channel.wHistory;

    int startIdx = -1;
    int len = [vList.length, aList.length, wList.length].reduce((a, b) => a < b ? a : b);
    for (int i = 0; i < len; i++) {
      if (vList[i].y > 0.05 && aList[i].y > 0.05 && wList[i].y > 0.05) {
        startIdx = i;
        break;
      }
    }

    bool isCharging = false;
    if (startIdx != -1 && vList.isNotEmpty && aList.isNotEmpty) {
      final lastV = vList.last.y;
      final lastA = aList.last.y;
      if (lastV > 0.05 && lastA > 0.05) {
        isCharging = true;
      }
    }

    if (startIdx != -1 && isCharging) {
      double startX = vList[startIdx].x;
      startTime = DateTime.now().subtract(Duration(milliseconds: (vList.last.x - startX).toInt() * 1000));
    } else {
      startTime = null;
    }
    DateTime now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text('Biểu đồ ${widget.channel.name}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (startTime != null)
                  Text(
                    'BẮT ĐẦU LÚC: ${_formatTime(startTime!)}',
                    style: TextStyle(fontSize: 16, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                  )
                else
                  SizedBox.shrink(),
                Text(
                  'HIỆN TẠI: ${_formatTime(now)}',
                  style: TextStyle(fontSize: 16, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (startTime != null && isCharging) ...[
            _buildChart('Điện áp (V)', vList, Colors.limeAccent, startIdx),
            SizedBox(height: 24),
            _buildChart('Dòng (A)', aList, Colors.orangeAccent, startIdx),
            SizedBox(height: 24),
            _buildChart('Công suất (W)', wList, Colors.pinkAccent, startIdx),
          ] else ...[
            Center(
              child: Column(
                children: [
                  Icon(Icons.battery_charging_full, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Chưa có dữ liệu sạc',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildChart(String label, List<FlSpot> data, Color color, int startIdx) {
    final plotData = (startIdx != -1 && startIdx < data.length) ? data.sublist(startIdx) : <FlSpot>[];

    double minY = 0;
    double maxY = plotData.isNotEmpty ? plotData.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 0.5 : 1;
    double minX = plotData.isNotEmpty ? plotData.first.x : 0;
    double maxX = plotData.isNotEmpty ? plotData.last.x : 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 180,
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1,
              maxScale: 5,
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(
                      border: Border.all(color: Colors.tealAccent, width: 1.5)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: plotData.map((e) => FlSpot(e.x, e.y)).toList(),
                      isCurved: false,
                      color: color,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          if (plotData.isNotEmpty && spot.x == plotData.last.x) {
                            return FlDotCirclePainter(
                              radius: 5,
                              color: Colors.redAccent,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            );
                          }
                          return FlDotCirclePainter(
                            radius: 0,
                            color: Colors.transparent,
                          );
                        },
                      ),
                    )
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: Colors.black87,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipRoundedRadius: 8,
                      getTooltipItems: (spots) {
                        if (spots.isEmpty) return [];
                        final spot = spots.first;
                        String valueStr = spot.y.toStringAsFixed(2);
                        String unitStr = label.contains('áp') ? 'V' : label.contains('Dòng') ? 'A' : 'W';

                        DateTime? t = startTime != null
                            ? startTime!.add(Duration(milliseconds: ((spot.x - plotData.first.x) * 1000).toInt()))
                            : null;
                        String timeLabel = t != null
                            ? "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}"
                            : "";

                        return [
                          LineTooltipItem(
                            '$valueStr $unitStr\n$timeLabel',
                            TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                  showingTooltipIndicators: [],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) =>
                            Text('${value.toStringAsFixed(1)}'),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => const SizedBox.shrink(),
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 32,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChargeSession {
  final DateTime start;
  final DateTime end;
  final List<FlSpot> vHistory;
  final List<FlSpot> aHistory;
  final List<FlSpot> wHistory;

  ChargeSession({
    required this.start,
    required this.end,
    required this.vHistory,
    required this.aHistory,
    required this.wHistory,
  });
}

class HistoryScreen extends StatelessWidget {
  final List<ChargeSession> history;
  const HistoryScreen({required this.history});

  @override
  Widget build(BuildContext context) {
    // Nhóm theo ngày
    Map<String, List<ChargeSession>> byDay = {};
    for (var s in history) {
      String day = "${s.start.year}-${s.start.month.toString().padLeft(2, '0')}-${s.start.day.toString().padLeft(2, '0')}";
      byDay.putIfAbsent(day, () => []).add(s);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: Text('Lịch sử sạc')),
      body: days.isEmpty
          ? Center(child: Text('Chưa có lịch sử sạc nào!', style: TextStyle(fontSize: 18)))
          : ListView.builder(
              itemCount: days.length,
              itemBuilder: (context, i) {
                final day = days[i];
                final sessions = byDay[day]!;
                return ExpansionTile(
                  leading: Icon(Icons.calendar_today, color: Colors.tealAccent),
                  title: Text(day, style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    ...sessions.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final s = entry.value;
                      return ListTile(
                        leading: Icon(Icons.battery_charging_full, color: Colors.orangeAccent),
                        title: Text(
                          'Lần ${idx + 1}: ${_formatTime(s.start)} - ${_formatTime(s.end)}',
                          style: TextStyle(fontSize: 16),
                        ),
                        subtitle: Text('Nhấn để xem đồ thị'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChartHistoryScreen(session: s),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                );
              },
            ),
    );
  }

  String _formatTime(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
}

class ChartHistoryScreen extends StatelessWidget {
  final ChargeSession session;
  const ChartHistoryScreen({required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Đồ thị phiên sạc'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BẮT ĐẦU: ${_formatTime(session.start)}',
                  style: TextStyle(fontSize: 16, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                ),
                Text(
                  'KẾT THÚC: ${_formatTime(session.end)}',
                  style: TextStyle(fontSize: 16, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          _buildChart('Điện áp (V)', session.vHistory, Colors.limeAccent),
          SizedBox(height: 24),
          _buildChart('Dòng (A)', session.aHistory, Colors.orangeAccent),
          SizedBox(height: 24),
          _buildChart('Công suất (W)', session.wHistory, Colors.pinkAccent),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  Widget _buildChart(String label, List<FlSpot> data, Color color) {
    double minY = 0;
    double maxY = data.isNotEmpty ? data.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 0.5 : 1;
    double minX = data.isNotEmpty ? data.first.x : 0;
    double maxX = data.isNotEmpty ? data.last.x : 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 180,
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1,
              maxScale: 5,
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(
                      border: Border.all(color: Colors.tealAccent, width: 1.5)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: false,
                      color: color,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          if (data.isNotEmpty && spot.x == data.last.x) {
                            return FlDotCirclePainter(
                              radius: 5,
                              color: Colors.redAccent,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            );
                          }
                          return FlDotCirclePainter(
                            radius: 0,
                            color: Colors.transparent,
                          );
                        },
                      ),
                    )
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: Colors.black87,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipRoundedRadius: 8,
                      getTooltipItems: (spots) {
                        if (spots.isEmpty) return [];
                        final spot = spots.first;
                        String valueStr = spot.y.toStringAsFixed(2);
                        String unitStr = label.contains('áp') ? 'V' : label.contains('Dòng') ? 'A' : 'W';
                        return [
                          LineTooltipItem(
                            '$valueStr $unitStr\n${spot.x.toStringAsFixed(1)} s',
                            TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                  showingTooltipIndicators: [],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) =>
                            Text('${value.toStringAsFixed(1)}'),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => const SizedBox.shrink(),
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 32,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Lưu / tải lịch sử
Future<void> saveHistory(List<ChargeSession> history) async {
  final prefs = await SharedPreferences.getInstance();
  final data = history.map((s) => jsonEncode({
    'start': s.start.toIso8601String(),
    'end': s.end.toIso8601String(),
    'v': s.vHistory.map((e) => [e.x, e.y]).toList(),
    'a': s.aHistory.map((e) => [e.x, e.y]).toList(),
    'w': s.wHistory.map((e) => [e.x, e.y]).toList(),
  })).toList();
  await prefs.setStringList('charge_history', data);
}

Future<List<ChargeSession>> loadHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getStringList('charge_history') ?? [];
  return data.map((s) {
    final map = jsonDecode(s);
    return ChargeSession(
      start: DateTime.parse(map['start']),
      end: DateTime.parse(map['end']),
      vHistory: (map['v'] as List).map((e) => FlSpot(e[0], e[1])).toList(),
      aHistory: (map['a'] as List).map((e) => FlSpot(e[0], e[1])).toList(),
      wHistory: (map['w'] as List).map((e) => FlSpot(e[0], e[1])).toList(),
    );
  }).toList();
}
