import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool _isConnected = true;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    print('DEBUG: Initializing NetworkService');

    // Check initial connectivity
    await _checkConnectivity();

    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      print('DEBUG: Connectivity changed to: $result');
      _updateConnectionStatus(result);
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      print('DEBUG: Checking connectivity...');
      final result = await _connectivity.checkConnectivity();
      print('DEBUG: Initial connectivity result: $result');

      // If we have a network interface, test actual internet connectivity
      if (result != ConnectivityResult.none) {
        final hasInternet = await _testInternetConnection();
        print('DEBUG: Internet connectivity test result: $hasInternet');
        _updateConnectionStatus(hasInternet ? result : ConnectivityResult.none);
      } else {
        _updateConnectionStatus(result);
      }
    } catch (e) {
      print('DEBUG: Error checking connectivity: $e');
      _updateConnectionStatus(ConnectivityResult.none);
    }
  }

  Future<bool> _testInternetConnection() async {
    try {
      // Try to connect to Google's DNS (8.8.8.8) on port 53
      final result = await InternetAddress('8.8.8.8').reverse();
      print('DEBUG: Internet test successful: $result');
      return true;
    } catch (e) {
      print('DEBUG: Internet test failed: $e');
      return false;
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    bool wasConnected = _isConnected;

    // Consider connected if we have any type of connection
    _isConnected = result != ConnectivityResult.none;

    print(
      'DEBUG: Connection status - was: $wasConnected, is: $_isConnected, result: $result',
    );

    if (wasConnected != _isConnected) {
      print('DEBUG: Connection status changed, notifying listeners');
      _connectionStatusController.add(_isConnected);
    }
  }

  // Manual check method for retry functionality
  Future<bool> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      print('DEBUG: Manual connectivity check result: $result');

      if (result != ConnectivityResult.none) {
        final hasInternet = await _testInternetConnection();
        print('DEBUG: Manual internet test result: $hasInternet');
        _updateConnectionStatus(hasInternet ? result : ConnectivityResult.none);
        return hasInternet;
      } else {
        _updateConnectionStatus(result);
        return false;
      }
    } catch (e) {
      print('DEBUG: Error in manual connection check: $e');
      _updateConnectionStatus(ConnectivityResult.none);
      return false;
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
