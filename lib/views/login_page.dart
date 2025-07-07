import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/student_viewmodel.dart';
import '../services/firebase_service.dart';
import '../services/network_service.dart';
import 'home_page.dart';
import 'no_network_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  String? _error;
  final NetworkService networkService = NetworkService();
  bool _isNetworkConnected = true;

  @override
  void initState() {
    super.initState();
    _checkNetworkStatus();
    _listenToNetworkChanges();
  }

  void _checkNetworkStatus() async {
    print('DEBUG: Checking network status in LoginPage');
    final isConnected = await networkService.checkConnection();
    if (mounted) {
      setState(() {
        _isNetworkConnected = isConnected;
      });
      print('DEBUG: LoginPage network status set to: $_isNetworkConnected');
    }
  }

  void _listenToNetworkChanges() {
    print('DEBUG: Setting up network listener in LoginPage');
    networkService.connectionStatus.listen((isConnected) {
      print('DEBUG: LoginPage received network status: $isConnected');
      if (mounted) {
        setState(() {
          _isNetworkConnected = isConnected;
        });
        print(
          'DEBUG: LoginPage network status updated to: $_isNetworkConnected',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show NoNetworkScreen if not connected
    if (!_isNetworkConnected) {
      return NoNetworkScreen(
        onRetry: () {
          _checkNetworkStatus();
        },
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade700, Colors.blue.shade500],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(60),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.school,
                      size: 60,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // App Title
                  Text(
                    'Student Fee Manager',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // App Description
                  Text(
                    'Manage student fee records with Excel files\nand sync data to the cloud',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Error Message
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Google Sign-In Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.login, size: 24),
                      label: Text(
                        _isLoading ? 'Signing in...' : 'Continue with Google',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Features List
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureItem(
                          Icons.upload_file,
                          'Upload Excel Files',
                          'Import student data from .xlsx files',
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          Icons.search,
                          'Search & Filter',
                          'Find students by name, school, or class',
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          Icons.edit,
                          'Edit Records',
                          'Add, edit, or delete student information',
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          Icons.cloud_sync,
                          'Cloud Sync',
                          'Your data is automatically backed up',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final firebaseService = FirebaseService();
      final userCredential = await firebaseService.signInWithGoogle();

      if (userCredential != null && userCredential.user != null) {
        // Clear and reload data for the new user
        final viewModel = Provider.of<StudentViewModel>(context, listen: false);
        await viewModel.clearAllData();
        await viewModel.loadDataFromCloud();

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } else {
        // User cancelled or sign-in failed
        setState(() {
          _error = 'Sign-in was cancelled or failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error signing in: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
