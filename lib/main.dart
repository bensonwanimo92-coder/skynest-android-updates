import 'package:flutter/material.dart';

void main() => runApp(const SkyNestApp());

class SkyNestApp extends StatelessWidget {
  const SkyNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkyNest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD4A017)),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = 'Tenant';
  bool obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4A017);
    return Scaffold(
      backgroundColor: gold,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: Row(
                children: const [
                  Icon(Icons.home_outlined, color: Colors.white, size: 36),
                  SizedBox(width: 12),
                  Text(
                    'SkyNest Chuka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          children: ['Landlord', 'Tenant', 'Caretaker'].map((role) {
                            final selected = selectedRole == role;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => selectedRole = role),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  decoration: BoxDecoration(
                                    color: selected ? gold : Colors.transparent,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Center(
                                    child: Text(
                                      role,
                                      style: TextStyle(
                                        color: selected ? Colors.white : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Welcome back!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Log in to continue as $selectedRole',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 28),
                      const TextField(
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() {
                              obscurePassword = !obscurePassword;
                            }),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(color: gold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const HomeScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'LOGIN',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: const [
                            Text("Don't have an account? "),
                            Text(
                              'Sign up',
                              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4A017);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyNest'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Welcome to SkyNest'),
      ),
    );
  }
}
