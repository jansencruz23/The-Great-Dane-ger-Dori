import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => currentUser != null;
  bool get isCaregiver => currentUser?.isCaregiver ?? false;
  bool get isPatient => currentUser?.isPatient ?? false;

  // Initialize user session
  Future<void> initializeUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      final firebaseUser = _authService.currentUser;

      if (firebaseUser != null) {
        _currentUser = await _databaseService.getUser(firebaseUser.uid);

        // Update last login
        if (_currentUser != null) {
          await _databaseService.updateUserLastLogin(_currentUser!.uid);
        }
      } else {
        _currentUser = null;
      }

      _error = null;
    } catch (e) {
      _error = e.toString();
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Login user
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final firebaseUser = await _authService.signInWithEmail(email, password);

      if (firebaseUser != null) {
        _currentUser = await _databaseService.getUser(firebaseUser.uid);

        // Update last login
        if (_currentUser != null) {
          await _databaseService.updateUserLastLogin(currentUser!.uid);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = 'Login failed';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Register new user
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String role,
    String? caregiverId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final firebaseUser = await _authService.createUserWithEmail(
        email,
        password,
      );

      if (firebaseUser != null) {
        final newUser = UserModel(
          uid: firebaseUser.uid,
          email: email,
          name: name,
          role: role,
          caregiverId: caregiverId,
          patientIds: role == 'caregiver' ? [] : null,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );

        await _databaseService.createUser(newUser);

        // If patient with caregiver, link them
        if (role == 'patient' && caregiverId != null) {
          await _databaseService.linkPatientToCaregiver(
            caregiverId,
            firebaseUser.uid,
          );
        }

        _currentUser = newUser;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = 'Registration failed';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout user
  Future<void> logout() async {
    await _authService.signOut();
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  // Refresh current user data
  Future<void> refreshUserData() async {
    if (_currentUser != null) {
      try {
        _currentUser = await _databaseService.getUser(_currentUser!.uid);
        notifyListeners();
      } catch (e) {
        _error = e.toString();
        notifyListeners();
      }
    }
  }

  // Update user profile
  Future<bool> updateProfile({String? name}) async {
    if (_currentUser == null) return false;

    try {
      final updatedUser = _currentUser!.copyWith(
        name: name ?? _currentUser!.name,
      );

      await _databaseService.updateUser(updatedUser);
      _currentUser = updatedUser;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
