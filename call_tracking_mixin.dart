import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:get/get.dart';
import 'package:MyGenie/call_state.dart';

mixin CallTrackingMixin<T extends StatefulWidget> on State<T> {
  final CallStateManager callStateManager = CallStateManager();
  static const MethodChannel platform = MethodChannel('callkit_channel');

  Timer? _callDurationTimer;
  bool _isCallActive = false;
  int _currentCallDuration = 0;
  int _callTimeDuration = 0;
  DateTime? _callStartTime;
  StreamController<int>? _durationController;
  int _lastKnownDuration = 0;
  bool _isApiCalled = false;

  @override
  void initState() {
    super.initState();
    print("InitState - Setting up call monitoring");
    _setupCallMonitoring();
    print("Call monitoring setup completed");
  }

  @override
  void dispose() {
    _durationController?.close();
    super.dispose();
  }

  Future<void> _setupCallMonitoring() async {
    if (Platform.isIOS) {
      print("Setting up call monitoring");
      _durationController?.close();
      _durationController = StreamController<int>.broadcast();

      platform.setMethodCallHandler((MethodCall call) async {
        print("Method call received: ${call.method}");

        if (!mounted) {
          print("Widget not mounted, returning");
          return;
        }

        switch (call.method) {
          case 'onCallStarted':
            print("Call started - Resetting states");
            setState(() {
              _isCallActive = true;
              _callStartTime = DateTime.now();
              _isApiCalled = false; // Reset here explicitly
            });
            print("Call states reset - isApiCalled: $_isApiCalled");
            break;

          case 'onCallEnded':
            print("Call ended event received");
            print("Current isApiCalled status: $_isApiCalled");
            if (call.arguments != null) {
              final Map<dynamic, dynamic> args = call.arguments;
              final int duration = args['duration'] as int;
              print("Processing call end with duration: $_callTimeDuration");

              // Force reset isApiCalled here
              setState(() {
                _isApiCalled = false;
              });

              await _handleCallEnded(_currentCallDuration);
            }
            setState(() {
              _isCallActive = false;
            });
            break;

          case 'onCallDurationUpdate':
            if (call.arguments != null && mounted) {
              final Map<dynamic, dynamic> args = call.arguments;
              final int duration = args['duration'] as int;
              setState(() {
                _currentCallDuration = duration;
                _lastKnownDuration = duration;
                _callTimeDuration = duration;
              });
              _durationController?.add(duration);
              print("Duration update: $duration seconds");
            }
            break;
        }
      });
    }
  }

  void resetCallState() {
    print("Resetting call state");
    setState(() {
      _isApiCalled = false;
      _isCallActive = false;
      _currentCallDuration = 0;
      _lastKnownDuration = 0;
      _callTimeDuration = 0;
      _callStartTime = null;
    });
    print("Call state reset completed - isApiCalled: $_isApiCalled");
  }

  Future<void> _handleCallEnded(int durationInSeconds) async {
    print("Entering _handleCallEnded");
    print("Current state - isApiCalled: $_isApiCalled, mounted: $mounted");
    print("Duration to process: $durationInSeconds seconds");

    // Force check and reset if needed
    if (_isApiCalled) {
      print("Resetting isApiCalled flag as it was true");
      setState(() {
        _isApiCalled = false;
      });
    }

    if (mounted) {
      final duration = Duration(seconds: durationInSeconds);
      final formattedDuration = _formatDuration(duration);
      print("Processing call end with duration: $formattedDuration");

      if (durationInSeconds == 0 && _callStartTime != null) {
        final fallbackDuration = DateTime.now().difference(_callStartTime!);
        final fallbackSeconds = fallbackDuration.inSeconds;
        print("Using fallback duration: $fallbackSeconds seconds");
        await _saveCallDuration(fallbackSeconds);
      } else {
        print("Using provided duration: $durationInSeconds seconds");
        await _saveCallDuration(durationInSeconds);
      }

      setState(() {
        _isApiCalled = true;
      });
      print("Call processing completed - isApiCalled set to true");
    } else {
      print("Widget not mounted, skipping call processing");
    }
  }

  Future<void> _saveCallDuration(int durationInSeconds) async {
    if (durationInSeconds > 0) {
      final formattedDuration =
          _formatDuration(Duration(seconds: durationInSeconds));
      print("Saving duration: $formattedDuration");

      if (callStateManager.callId.isNotEmpty) {
        saveRandomCallDuration(formattedDuration);
      }
      if (callStateManager.leadCallId.isNotEmpty) {
        saveCallDuration(formattedDuration);
      }
    } else {
      print("Warning: Attempting to save zero duration");
    }
  }

  void saveCallDuration(String duration);
  void saveRandomCallDuration(String duration);

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours =
        duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : '';
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours$minutes:$seconds';
  }

  void resetCallTracking() {
    _setupCallMonitoring();
  }
}
