import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyC7IrrCvkc7wzg2wZIMjQKTxNgSEqi4uF4",
      authDomain: "drivewise-mad-2026.firebaseapp.com",
      projectId: "drivewise-mad-2026",
      storageBucket: "drivewise-mad-2026.firebasestorage.app",
      messagingSenderId: "353020906026",
      appId: "1:353020906026:web:485f0656a53b6082e05153",
    ),
  );
  runApp(const DriveWiseApp());
}

class DriveWiseApp extends StatefulWidget {
  const DriveWiseApp({super.key});
  @override State<DriveWiseApp> createState() => _DriveWiseAppState();
}

class _DriveWiseAppState extends State<DriveWiseApp> {
  Position? _currentPosition;
  double _currentSpeed = 0.0;
  int _score = 100;
  bool _isDriving = false;
  int _totalPoints = 0;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelerometerStream;
  FlutterTts? _tts;
  double _speedLimit = 25.0; // Default, will fetch real

  @override void initState() {
    super.initState();
    _tts = FlutterTts();
    _checkPermissionAndStart();
  }

  Future<void> _checkPermissionAndStart() async {
    // Location permission
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _speak("Please enable location services");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Start streams
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        _currentSpeed = position.speed * 2.23694; // m/s to mph
      });

      _fetchSpeedLimit(position.latitude, position.longitude);
      _checkTripState();
      if (_isDriving) _updateScore();
    });

    _accelerometerStream = accelerometerEvents.listen((AccelerometerEvent event) {
      if (_isDriving && event.z.abs() > 15) { // Harsh brake/accel
        _deductPoints(5, "Harsh maneuver!");
      }
    });
  }

  Future<void> _fetchSpeedLimit(double lat, double lon) async {
    // Simple OpenStreetMap API call for speed limit (mock for demo)
    try {
      final response = await http.get(Uri.parse(
        'https://overpass-api.de/api/interpreter?data=[out:json];way(around:10,$lat,$lon)[highway];out;'
      ));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Mock parsing - in real: extract maxspeed tag
        setState(() => _speedLimit = 25.0 + Random().nextDouble() * 5); // Demo variation
      }
    } catch (e) {
      _speedLimit = 25.0;
    }
  }

  void _checkTripState() {
    if (_currentSpeed > 10 && !_isDriving) {
      _startTrip();
    } else if (_currentSpeed < 2 && _isDriving) {
      _endTrip();
    }
  }

  void _startTrip() {
    setState(() => _isDriving = true);
    _speak("Trip started. Drive safe!");
    _score = 100; // Reset score per trip
  }

  Future<void> _endTrip() async {
    setState(() => _isDriving = false);
    _totalPoints += _score ~/ 2; // Earn half score as points
    await FirebaseFirestore.instance.collection('trips').add({
      'score': _score,
      'points_earned': _score ~/ 2,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': 'demo_user', // Add auth later
    });
    _speak("Trip ended! Score: $_score out of 100. Earned ${_score ~/ 2} points.");
    _showLeaderboard();
  }

  void _updateScore() {
    if (_currentSpeed > _speedLimit + 3) {
      _deductPoints(2, "Speeding! Limit is $_speedLimit mph");
    } else {
      _addPoints(1, "Smooth driving!");
    }
  }

  void _addPoints(int pts, String reason) {
    setState(() => _score = (_score + pts).clamp(0, 100));
    _speak(reason);
    HapticFeedback.vibrate();
  }

  void _deductPoints(int pts, String reason) {
    setState(() => _score = (_score - pts).clamp(0, 100));
    _speak(reason);
    HapticFeedback.vibrate();
  }

  Future<void> _speak(String text) async {
    await _tts?.setLanguage("en-US");
    await _tts?.speak(text);
  }

  void _showLeaderboard() {
    // Navigate to leaderboard screen (simple modal for now)
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leaderboard"),
        content: const Text("You: #1 (Demo)\nFriend1: 92\nFriend2: 88"), // Real Firebase later
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  void _showPerks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Perks - Total Points: $_totalPoints"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_totalPoints >= 500) const ListTile(title: Text("Free Coffee Unlocked!"), subtitle: Text("Scan QR below")),
            // Add QrImage(qrData: "perk:coffee") here in full version
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Redeem")),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriveWise',
      theme: ThemeData(primarySwatch: Colors.green),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('DRIVEWISE'),
          actions: [
            IconButton(
              icon: const Icon(Icons.star),
              onPressed: _showPerks,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isDriving ? '🚗 DRIVING MODE' : 'Ready to Drive',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isDriving ? Colors.green : Colors.grey),
                ),
                const SizedBox(height: 20),
                Text('Speed: ${_currentSpeed.toStringAsFixed(1)} mph', style: const TextStyle(fontSize: 18)),
                Text('Limit: ${_speedLimit.toStringAsFixed(0)} mph', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
                Text('Trip Score: $_score / 100', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                Text('Total Points: $_totalPoints', style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 20),
                if (_isDriving) Text('Stay under ${_speedLimit.toStringAsFixed(0)} mph!', style: const TextStyle(color: Colors.orange, fontSize: 16)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _showLeaderboard,
                  child: const Text('View Leaderboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override void dispose() {
    _positionStream?.cancel();
    _accelerometerStream?.cancel();
    _tts?.stop();
    super.dispose();
  }
}
