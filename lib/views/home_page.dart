import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../viewmodels/student_viewmodel.dart';
import '../views/student_detail_page.dart';
import '../views/add_edit_student_page.dart';
import '../services/firebase_service.dart';
import '../services/network_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
import '../views/login_page.dart';
import 'no_network_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseService firebaseService = FirebaseService();
  final NetworkService networkService = NetworkService();
  bool _isNetworkConnected = true;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _checkNetworkStatus();
    _listenToNetworkChanges();
    // Initialize the ViewModel when the page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentViewModel>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _checkNetworkStatus() async {
    print('DEBUG: Checking network status in HomePage');
    final isConnected = await networkService.checkConnection();
    if (mounted) {
      setState(() {
        _isNetworkConnected = isConnected;
      });
      print('DEBUG: HomePage network status set to: $_isNetworkConnected');
    }
  }

  void _listenToNetworkChanges() {
    print('DEBUG: Setting up network listener in HomePage');
    networkService.connectionStatus.listen((isConnected) {
      print('DEBUG: HomePage received network status: $isConnected');
      if (mounted) {
        setState(() {
          _isNetworkConnected = isConnected;
        });
        print(
          'DEBUG: HomePage network status updated to: $_isNetworkConnected',
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
      appBar: AppBar(
        title: const Text('Student Fee Manager'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          // Network status indicator
          if (!_isNetworkConnected)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          // User info and sign out
          Consumer<StudentViewModel>(
            builder: (context, viewModel, child) {
              final user = FirebaseAuth.instance.currentUser;
              return PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'profile':
                      _showUserProfile(context, user);
                      break;
                    case 'sync':
                      if (viewModel.isLoading) break;
                      try {
                        await viewModel.syncToCloud(viewModel.fileName!);
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Data synced to cloud successfully!',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: Colors.green,
                            textColor: Colors.white,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Sync failed: $e',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: Colors.red,
                            textColor: Colors.white,
                          );
                        }
                      }
                      break;
                    case 'export':
                      try {
                        final bytes = await viewModel.exportToExcel();
                        final directory = await getExternalStorageDirectory();
                        final path = directory?.path ?? '/';
                        final fileName =
                            viewModel.fileName != null &&
                                viewModel.fileName!.endsWith('.xlsx')
                            ? viewModel.fileName!
                            : 'student_fees_export.xlsx';
                        final file = File('$path/$fileName');
                        await file.writeAsBytes(bytes);
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Exported to $path/$fileName',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Export failed: $e',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                          );
                        }
                      }
                      break;
                    case 'clear':
                      try {
                        viewModel.clearFilters();
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Filters cleared',
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: Colors.green,
                            textColor: Colors.white,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Failed to clear filters: $e',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: Colors.red,
                            textColor: Colors.white,
                          );
                        }
                      }
                      break;
                    case 'clear_data':
                      final result = await showDialog<_ClearAllResult>(
                        context: context,
                        builder: (context) => _ClearAllDialog(),
                      );
                      if (result == null) break;
                      try {
                        if (result.clearFromFirestore) {
                          if (result.confirmText == 'CLEAR') {
                            await viewModel.clearAllDataFromFirestore();
                          } else {
                            Fluttertoast.showToast(
                              msg:
                                  'You must type CLEAR to confirm database deletion.',
                              toastLength: Toast.LENGTH_LONG,
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: Colors.red,
                              textColor: Colors.white,
                            );
                            break;
                          }
                        }
                        await viewModel.clearAllData();
                        if (mounted) {
                          if (result.clearFromFirestore) {
                            Fluttertoast.showToast(
                              msg: 'All data cleared from app and database',
                              toastLength: Toast.LENGTH_LONG,
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: Colors.green,
                              textColor: Colors.white,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('All data cleared from app'),
                                action: SnackBarAction(
                                  label: 'Reload from Cloud',
                                  onPressed: () async {
                                    await viewModel.loadDataFromCloud();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Data loaded from cloud!',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          Fluttertoast.showToast(
                            msg: 'Failed to clear data: $e',
                            toastLength: Toast.LENGTH_LONG,
                            gravity: ToastGravity.BOTTOM,
                            backgroundColor: Colors.red,
                            textColor: Colors.white,
                          );
                        }
                      }
                      break;
                    case 'signout':
                      await _signOut(context);
                      break;
                    case 'reload_cloud':
                      try {
                        await viewModel.loadDataFromCloud();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Data loaded from cloud!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error loading from cloud: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                      break;
                    case 'select_file':
                      await _showFileSelectionDialog(context);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  // User profile section
                  PopupMenuItem(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Signed in as',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          user?.email ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  // Reload from Cloud option (always available)
                  const PopupMenuItem(
                    value: 'reload_cloud',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_download),
                        SizedBox(width: 8),
                        Text('Reload from Cloud'),
                      ],
                    ),
                  ),
                  // Select File option (always available)
                  const PopupMenuItem(
                    value: 'select_file',
                    child: Row(
                      children: [
                        Icon(Icons.folder_open),
                        SizedBox(width: 8),
                        Text('Select File'),
                      ],
                    ),
                  ),
                  // Sync option
                  if (viewModel.fileName != null)
                    const PopupMenuItem(
                      value: 'sync',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_sync),
                          SizedBox(width: 8),
                          Text('Sync to Cloud'),
                        ],
                      ),
                    ),
                  // Export option
                  if (viewModel.fileName != null)
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.download),
                          SizedBox(width: 8),
                          Text('Export Data'),
                        ],
                      ),
                    ),
                  // Clear filters
                  if (viewModel.fileName != null)
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all),
                          SizedBox(width: 8),
                          Text('Clear Filters'),
                        ],
                      ),
                    ),
                  // Clear data
                  if (viewModel.fileName != null)
                    const PopupMenuItem(
                      value: 'clear_data',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Clear All Data',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  // Sign out
                  const PopupMenuItem(
                    value: 'signout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<StudentViewModel>(
        builder: (context, viewModel, child) {
          // Show loading while initializing
          if (!viewModel.isInitialized) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading saved data...'),
                ],
              ),
            );
          }

          if (viewModel.isLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    viewModel.students.isEmpty
                        ? 'Loading Excel file...'
                        : 'Processing large file...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (viewModel.students.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${viewModel.students.length} records processed',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          if (viewModel.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    viewModel.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => viewModel.loadExcelFile(),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }

          if (!viewModel.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 64,
                    color: Colors.blue.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Upload Excel File',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select an Excel file to manage student fee records',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => viewModel.loadExcelFile(),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Choose Excel File'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildHeader(context, viewModel),
              _buildFilters(context, viewModel),
              Expanded(child: _buildStudentList(context, viewModel)),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<StudentViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.fileName != null) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Manual sync button
                if (viewModel.isAuthenticated)
                  FloatingActionButton.small(
                    onPressed: viewModel.isLoading
                        ? null
                        : () async {
                            try {
                              await viewModel.syncToCloud(viewModel.fileName!);
                              if (mounted) {
                                Fluttertoast.showToast(
                                  msg: 'Data synced to cloud successfully!',
                                  toastLength: Toast.LENGTH_LONG,
                                  gravity: ToastGravity.BOTTOM,
                                  backgroundColor: Colors.green,
                                  textColor: Colors.white,
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                Fluttertoast.showToast(
                                  msg: 'Sync failed: $e',
                                  toastLength: Toast.LENGTH_LONG,
                                  gravity: ToastGravity.BOTTOM,
                                  backgroundColor: Colors.red,
                                  textColor: Colors.white,
                                );
                              }
                            }
                          },
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    tooltip: 'Sync to Cloud',
                    child: viewModel.isLoading
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
                        : const Icon(Icons.cloud_sync),
                  ),
                const SizedBox(height: 8),
                // Add student button
                FloatingActionButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddEditStudentPage(),
                      ),
                    );
                  },
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, StudentViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  viewModel.fileName!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                context,
                'Total Students',
                viewModel.students.length.toString(),
                Icons.people,
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                context,
                'Showing',
                viewModel.filteredStudents.length.toString(),
                Icons.filter_list,
                Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context, StudentViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // Unified Filter Chips
          if (viewModel.availableFilters.isNotEmpty) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.filter_list,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Filter by Standard/Class/Division',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (viewModel.selectedFilter != 'All')
                      TextButton(
                        onPressed: () => viewModel.setFilter('All'),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: viewModel.availableFilters.length,
                    itemBuilder: (context, index) {
                      final filter = viewModel.availableFilters[index];
                      final isSelected = viewModel.selectedFilter == filter;
                      if (filter.trim().isEmpty) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            filter == 'All' ? 'All' : filter,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.blue.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            viewModel.setFilter(selected ? filter : 'All');
                          },
                          backgroundColor: Colors.blue.shade50,
                          selectedColor: Colors.blue.shade600,
                          checkmarkColor: Colors.white,
                          side: BorderSide(
                            color: isSelected
                                ? Colors.blue.shade600
                                : Colors.blue.shade200,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search students...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: viewModel.isPendingFilterActive
                      ? Colors.blue
                      : Colors.grey,
                ),
                onPressed: () async {
                  double tempMinPending = viewModel.pendingFeesMinFilter ?? 0.0;
                  bool tempOnlyPending = viewModel.onlyPendingFeesFilter;
                  final controller = TextEditingController(
                    text: tempMinPending > 0 ? tempMinPending.toString() : '',
                  );
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AlertDialog(
                            title: const Text('Filter Students'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CheckboxListTile(
                                  value: tempOnlyPending,
                                  onChanged: (val) => setState(
                                    () => tempOnlyPending = val ?? false,
                                  ),
                                  title: const Text(
                                    'Show only students with pending fees',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Pending fees above (₹)',
                                  ),
                                  controller: controller,
                                  onChanged: (val) {
                                    setState(
                                      () => tempMinPending =
                                          double.tryParse(val) ?? 0.0,
                                    );
                                  },
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  viewModel.setPendingFeesFilter(
                                    tempOnlyPending,
                                    tempMinPending,
                                  );
                                  Navigator.pop(context);
                                },
                                child: const Text('Apply'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => viewModel.setSearchQuery(value),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildStudentList(BuildContext context, StudentViewModel viewModel) {
    if (viewModel.filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: viewModel.filteredStudents.length,
      itemBuilder: (context, index) {
        final student = viewModel.filteredStudents[index];
        return _buildStudentCard(context, student, index);
      },
    );
  }

  Widget _buildStudentCard(BuildContext context, student, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header with student name and actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    student.name.isNotEmpty
                        ? student.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              student.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (student.standard.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                student.standard,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (student.school.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          student.school,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AddEditStudentPage(studentId: student.id),
                          ),
                        );
                      },
                      icon: Icon(Icons.edit, color: Colors.blue.shade600),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                StudentDetailPage(studentId: student.id),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.visibility,
                        color: Colors.green.shade600,
                      ),
                      tooltip: 'View Details',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Student information
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Personal Info Section
                _buildInfoSection(
                  context,
                  'Personal Information',
                  Icons.person,
                  [
                    if (student.division.isNotEmpty)
                      _buildInfoRow('Division', student.division),
                    // Add more personal info fields here
                  ],
                ),

                const SizedBox(height: 16),

                // Fee Information Section
                _buildFeeSection(context, student),

                const SizedBox(height: 16),

                // All Data Section (collapsible)
                _buildAllDataSection(context, student),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blue.shade600, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildFeeSection(BuildContext context, student) {
    final totalFees = student.totalFeesAmount;
    final paidFees = student.paidFeesAmount;
    final pendingFees = student.pendingFeesAmount;
    final progress = totalFees > 0 ? paidFees / totalFees : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.currency_rupee, color: Colors.green.shade600, size: 20),
            const SizedBox(width: 8),
            Text(
              'Fee Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFeeCard(
                'Total Fees',
                '₹${totalFees.toStringAsFixed(0)}',
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildFeeCard(
                'Paid Fees',
                '₹${paidFees.toStringAsFixed(0)}',
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildFeeCard(
                'Pending',
                '₹${pendingFees.toStringAsFixed(0)}',
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Progress',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: progress >= 1.0 ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeeCard(String title, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: 16,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllDataSection(BuildContext context, student) {
    return Consumer<StudentViewModel>(
      builder: (context, viewModel, child) {
        return ExpansionTile(
          title: Row(
            children: [
              Icon(Icons.data_usage, color: Colors.purple.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'All Data Fields',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: viewModel.columns
                    .map(
                      (column) => _buildInfoRow(
                        column,
                        student.data[column]?.toString() ?? 'Not specified',
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserProfile(BuildContext context, User? user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${user?.email ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Name: ${user?.displayName ?? 'Not provided'}'),
            const SizedBox(height: 8),
            Text('User ID: ${user?.uid ?? 'Unknown'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await firebaseService.signOut();

      // Clear local data after sign out
      final viewModel = Provider.of<StudentViewModel>(context, listen: false);
      await viewModel.clearAllData();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showFileSelectionDialog(BuildContext context) async {
    final viewModel = Provider.of<StudentViewModel>(context, listen: false);

    try {
      final files = await viewModel.getAvailableFiles();

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No files found in cloud'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Select File from Cloud'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final uploadDate = file['uploadDate'] as Timestamp?;
                  final dateString = uploadDate != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          uploadDate.millisecondsSinceEpoch,
                        ).toString().split('.')[0]
                      : 'Unknown date';

                  return ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(file['fileName'] ?? 'Unknown'),
                    subtitle: Text(
                      '${file['studentCount']} students • $dateString',
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await viewModel.loadDataFromFile(file['fileId']);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Loaded: ${file['fileName']}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading files: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ClearAllResult {
  final bool clearFromFirestore;
  final String confirmText;
  _ClearAllResult({
    required this.clearFromFirestore,
    required this.confirmText,
  });
}

class _ClearAllDialog extends StatefulWidget {
  @override
  State<_ClearAllDialog> createState() => _ClearAllDialogState();
}

class _ClearAllDialogState extends State<_ClearAllDialog> {
  bool _clearFromFirestore = false;
  String _confirmText = '';
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear All Data'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Do you want to clear all data from the app only, or from the database also?',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _clearFromFirestore,
            onChanged: (val) =>
                setState(() => _clearFromFirestore = val ?? false),
            title: const Text('Clear from database (Firestore) also'),
          ),
          if (_clearFromFirestore) ...[
            const SizedBox(height: 8),
            const Text('Type CLEAR in all caps to confirm database deletion:'),
            TextField(
              onChanged: (val) => setState(() => _confirmText = val),
              decoration: const InputDecoration(hintText: 'Type CLEAR'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              _ClearAllResult(
                clearFromFirestore: _clearFromFirestore,
                confirmText: _confirmText,
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
