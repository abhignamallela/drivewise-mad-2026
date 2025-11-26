import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:http/http.dart' as http;
import 'package:aad_oauth/aad_oauth.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

void main() {
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
  double _speedLimit = 25.0;

  // Azure Config (replace with yours)
  final String _tenantId = 'YOUR_TENANT_ID';  // From AD B2C
  final String _clientId = 'YOUR_CLIENT_ID';  // From App Registration
  final String _cosmosEndpoint = 'https://YOUR_COSMOS_ACCOUNT.documents.azure.com:443/';
  final String _cosmosKey = 'YOUR_PRIMARY_KEY';  // From Keys tab
  final AadOAuth _oauth = AadOAuth(AzureADAuthConfig(
    tenant: 'YOUR_TENANT_ID',
    clientId: 'YOUR_CLIENT_ID',
    scope: 'openid profile offline_access',
    redirectUri: 'msauth.com.isu.drivewise://auth',  // Adjust for your app
  ));

  @override void initState() {
    super.initState();
    _tts = FlutterTts();
    _initAzureAuth();  // Login on start (anonymous/demo)
    _checkPermissionAndStart();
  }

  Future<void> _initAzureAuth() async {
    try {
      final result = await _oauth.logIn();  // Triggers AD B2C flow (demo: anonymous)
      if (result.isSucceeded) {
        print('Azure Auth Success: ${result.accessToken}');
        // Use token for Cosmos calls
      }
    } catch (e) {
      print('Auth Error: $e');  // Fallback to demo mode
    }
  }

  Future<void> _checkPermissionAndStart() async {
    // Same as before (location/motion)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        _currentSpeed = position.speed * 2.23694;  // m/s to mph
      });
      _fetchSpeedLimit(position.latitude, position.longitude);
      _checkTripState();
      if (_isDriving) _updateScore();
    });

    _accelerometerStream = accelerometerEvents.listen((AccelerometerEvent event) {
      if (_isDriving && event.z.abs() > 15) _deductPoints(5, "Harsh maneuver!");
    });
  }

  Future<void> _fetchSpeedLimit(double lat, double lon) async {
    // Same OSM mock
    try {
      final response = await http.get(Uri.parse(
        'https://overpass-api.de/api/interpreter?data=[out:json];way(around:10,$lat,$lon)[highway];out;',
      ));
      if (response.statusCode == 200) {
        setState(() => _speedLimit = 25.0 + Random().nextDouble() * 5);
      }
    } catch (e) {
      _speedLimit = 25.0;
    }
  }

  void _checkTripState() {
    if (_currentSpeed > 10 && !_isDriving) _startTrip();
    else if (_currentSpeed < 2 && _isDriving) _endTrip();
  }

  void _startTrip() {
    setState(() => _isDriving = true);
    _speak("Trip started. Drive safe!");
    _score = 100;
  }

  Future<void> _endTrip() async {
    setState(() => _isDriving = false);
    _totalPoints += _score ~/ 2;
    await _saveTripToCosmos(_score, _score ~/ 2);  // Azure Cosmos call
    _speak("Trip ended! Score: $_score/100. Earned ${_score ~/ 2} points.");
    _showLeaderboard();
  }

  Future<void> _saveTripToCosmos(int score, int points) async {
    // Simple REST insert (use azure_cosmos for full SDK)
    final body = json.encode({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'score': score,
      'pointsEarned': points,
      'timestamp': DateTime.now().toIso8601String(),
      'userId': 'demo_user',  // From auth token
    });
    final response = await http.post(
      Uri.parse('$_cosmosEndpointdbs/drivewisedb/colls/trips/docs'),
      headers: {
        'Authorization': 'type=aad&ver=1.0&sig=...' ,  // Use your Cosmos key or token
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode != 201) print('Cosmos Error: ${response.body}');
  }

  void _updateScore() {
    if (_currentSpeed > _speedLimit + 3) _deductPoints(2, "Speeding! Limit $_speedLimit mph");
    else _addPoints(1, "Smooth driving!");
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
    // Mock for now; query Cosmos in full
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leaderboard (Azure Cosmos)"),
        content: const Text("You: #1\nFriend1: 92\nFriend2: 88"),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriveWise Azure',
      theme: ThemeData(primarySwatch: Colors.blue),  // Azure blue!
      home: Scaffold(
        appBar: AppBar(title: const Text('DRIVEWISE'), actions: [IconButton(icon: const Icon(Icons.star), onPressed: _showLeaderboard)]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_isDriving ? '🚗 DRIVING MODE' : 'Ready to Drive', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isDriving ? Colors.green : Colors.grey)),
                const SizedBox(height: 20),
                Text('Speed: ${_currentSpeed.toStringAsFixed(1)} mph', style: const TextSize(18)),
                Text('Limit: ${_speedLimit.toStringAsFixed(0)} mph', style: const TextSize(18)),
                const SizedBox(height: 20),
                Text('Trip Score: $_score / 100', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                Text('Total Points: $_totalPoints', style: const TextStyle(fontSize: 24)),
                if (_isDriving) Text('Stay under ${_speedLimit.toStringAsFixed(0)} mph!', style: const TextStyle(color: Colors.orange, fontSize: 16)),
                const SizedBox(height: 40),
                ElevatedButton(onPressed: _showLeaderboard, child: const Text('View Leaderboard')),
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
