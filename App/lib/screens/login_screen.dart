import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController(text: ApiConfig.baseUrl);

  bool _obscurePassword = true;
  bool _showServerConfig = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password')),
      );
      return;
    }

    if (_serverController.text.trim().isNotEmpty) {
      await ApiConfig.setBaseUrl(_serverController.text.trim());
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final success = await auth.login(email, password);

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Sign in failed'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: isDark ? WhatsAppTheme.bgDark : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: WhatsAppTheme.primaryGreen,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: WhatsAppTheme.primaryGreen.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.chat_bubble_rounded, size: 44, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Welcome to Zelon',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF111B21),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in with your user or admin account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),

                // Email field
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined, color: WhatsAppTheme.primaryGreen),
                    filled: true,
                    fillColor: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: WhatsAppTheme.primaryGreen, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: WhatsAppTheme.primaryGreen),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: WhatsAppTheme.primaryGreen, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Server Configuration Toggle
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showServerConfig = !_showServerConfig),
                    icon: Icon(
                      _showServerConfig ? Icons.keyboard_arrow_up : Icons.settings,
                      size: 16,
                      color: WhatsAppTheme.primaryGreen,
                    ),
                    label: Text(
                      _showServerConfig ? 'Hide Server URL' : 'Server Settings',
                      style: const TextStyle(fontSize: 13, color: WhatsAppTheme.primaryGreen),
                    ),
                  ),
                ),

                if (_showServerConfig) ...[
                  TextField(
                    controller: _serverController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Server API URL',
                      hintText: 'http://your-server-ip:3000',
                      prefixIcon: const Icon(Icons.dns_outlined, color: WhatsAppTheme.primaryGreen),
                      filled: true,
                      fillColor: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 16),

                // Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'SIGN IN',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Info note
                Text(
                  'End-to-end encrypted engine · WhatsApp Multi-Device Protocol',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
