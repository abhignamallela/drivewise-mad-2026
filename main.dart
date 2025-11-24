import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DriveWiseApp());
}

class DriveWiseApp extends StatefulWidget {
  const DriveWiseApp({super.key});
  @override State<DriveWiseApp> createState() => _DriveWiseAppState();
}

class _DriveWiseAppState extends State<DriveWiseApp> {
  Position? _currentPosition;
  double _currentSpeed = 0;
  int _score = 100;
  bool _isDriving = false;
  StreamSubscription<Position>? _positionStream;

  final int _speedLimit = 25; // mph (campus default)

  @override void initState() {
    super.initState();
    _checkPermissionAndStart();
  }

  Future<void> _checkPermissionAndStart() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        _currentSpeed = position.speed * 2.23694; // m/s → mph
      });

      if (_currentSpeed > 10 && !_isDriving) {
        _startTrip();
      } else if (_currentSpeed < 2 && _isDriving) {
        _endTrip();
      }

      _updateScore();
    });

    accelerometerEvents.listen((event) {
      if (event.z > 15 && _isDriving) _deductPoints(5, "Harsh brake!");
    });
  }

  void _startTrip() {
    setState(() => _isDriving = true);
    _showNotification("Trip started! Drive safe.");
  }

  void _endTrip() async {
    setState(() => _isDriving = false);
    await FirebaseFirestore.instance.collection('trips').add({
      'score': _score,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': 'demo_user',
    });
    _showNotification("Trip ended! Score: $_score/100");
  }

  void _updateScore() {
    if (_currentSpeed > _speedLimit + 3) {
      _deductPoints(2, "Speeding!");
    } else if (_currentSpeed <= _speedLimit) {
      _addPoints(1, "Smooth!");
    }
  }

  void _deductPoints(int pts, String reason) async {
    if (_score > 0) {
      setState(() => _score -= pts);
      await Haptics.vibrate(HapticsType.error);
      _speak("$reason -$_pts pts");
    }
  }

  void _addPoints(int pts, String reason) async {
    setState(() => _score = (_score + pts).clamp(0, 100));
    await Haptics.vibrate(HapticsType.success);
    _speak("+$pts pts");
  }

  void _speak(String text) {
    // Use flutter_tts in production
    print("VOICE: $text");
  }

  void _showNotification(String msg) {
    // Use flutter_local_notifications
    print("NOTIF: $msg");
  }

  @override Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("DRIVEWISE")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_isDriving ? "DRIVING" : "IDLE",
                  style: TextStyle(fontSize: 32, color: _isDriving ? Colors.green : Colors.grey)),
              Text("Speed: ${_currentSpeed.toStringAsFixed(1)} mph",
                  style: const TextStyle(fontSize: 24)),
              Text("Score: $_score/100", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              if (_isDriving)
                const Text("Stay under 25 mph!", style: TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      ),
    );
  }

  @override void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
