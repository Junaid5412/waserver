import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/lock_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final bool isSetup;
  final Function(String pin)? onPinCreated;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    this.isSetup = false,
    this.onPinCreated,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _enteredPin = '';
  String? _errorMessage;
  bool _confirmMode = false;
  String _firstPin = '';

  void _onDigitPress(String digit) {
    if (_enteredPin.length >= 6) return;
    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4 || _enteredPin.length == 6) {
      // Check in setup or verify
      _handleSubmit();
    }
  }

  void _onDeletePress() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _handleSubmit() {
    final lockService = Provider.of<LockService>(context, listen: false);

    if (widget.isSetup) {
      if (!_confirmMode) {
        setState(() {
          _firstPin = _enteredPin;
          _enteredPin = '';
          _confirmMode = true;
        });
      } else {
        if (_enteredPin == _firstPin) {
          widget.onPinCreated?.call(_enteredPin);
          widget.onUnlocked();
        } else {
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _enteredPin = '';
            _firstPin = '';
            _confirmMode = false;
          });
        }
      }
    } else {
      if (lockService.verifyPin(_enteredPin)) {
        widget.onUnlocked();
      } else {
        setState(() {
          _errorMessage = 'Incorrect PIN. Please try again.';
          _enteredPin = '';
        });
      }
    }
  }

  Widget _buildKeypadButton(String digit, {String? sub}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => _onDigitPress(digit),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (sub != null)
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async => false, // prevent back without unlock
      child: Scaffold(
        backgroundColor: isDark ? WhatsAppTheme.bgDark : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Shield Icon with Lock
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: WhatsAppTheme.primaryGreen,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                widget.isSetup
                    ? (_confirmMode ? 'Confirm your new PIN' : 'Create an App PIN')
                    : 'Zelon Messenger Locked',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isSetup
                    ? 'Enter 4 digits to secure your messages'
                    : 'Enter your PIN to access your conversations',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),

              // PIN Dots (4 dots)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? WhatsAppTheme.primaryGreen
                          : (isDark ? Colors.white24 : Colors.grey.shade300),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: WhatsAppTheme.primaryGreen.withOpacity(0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],

              const Spacer(),

              // Numeric Keypad Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildKeypadButton('1'),
                        _buildKeypadButton('2', sub: 'ABC'),
                        _buildKeypadButton('3', sub: 'DEF'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildKeypadButton('4', sub: 'GHI'),
                        _buildKeypadButton('5', sub: 'JKL'),
                        _buildKeypadButton('6', sub: 'MNO'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildKeypadButton('7', sub: 'PQRS'),
                        _buildKeypadButton('8', sub: 'TUV'),
                        _buildKeypadButton('9', sub: 'WXYZ'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Biometric icon placeholder
                        InkWell(
                          onTap: () {
                            // Biometric quick check
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Touch fingerprint sensor on device')),
                            );
                          },
                          borderRadius: BorderRadius.circular(40),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(shape: BoxShape.circle),
                            child: const Icon(
                              Icons.fingerprint_rounded,
                              size: 34,
                              color: WhatsAppTheme.primaryGreen,
                            ),
                          ),
                        ),
                        _buildKeypadButton('0'),
                        // Delete Button
                        InkWell(
                          onTap: _onDeletePress,
                          borderRadius: BorderRadius.circular(40),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(shape: BoxShape.circle),
                            child: Icon(
                              Icons.backspace_outlined,
                              size: 24,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
