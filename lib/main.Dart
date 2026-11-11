import 'package:flutter/material.dart';

void main() => runApp(SkyNestApp());

class SkyNestApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}

// ===== LOGIN NA 3 ROLES - FIX YA OVERLAP =====
class LoginScreen extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = 'Tenant';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFD4A017),
      body: Column(
        children: [
          SizedBox(height: 60),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.home_outlined, color: Colors.white, size: 36),
                SizedBox(width: 12),
                Text('SkyNest Chuka', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(30)),
                      child: Row(
                        children: ['Landlord', 'Tenant', 'Caretaker'].map((role) {
                          bool isSelected = selectedRole == role;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => selectedRole = role),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(color: isSelected ? Color(0xFFD4A017) : Colors.transparent, borderRadius: BorderRadius.circular(30)),
                                child: Center(child: Text(role, style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold))),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    SizedBox(height: 30),
                    Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    Text('Log in to continue as $selectedRole', style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 30),
                    TextField(decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), hintText: 'you@example.com', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    SizedBox(height: 16),
                    TextField(obscureText: true, decoration: InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock), suffixIcon: Icon(Icons.visibility_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () {}, child: Text('Forgot password?', style: TextStyle(color: Color(0xFFD4A017))))),
                    SizedBox(height: 20),
                    SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD4A017), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => HomeScreen())); }, child: Text('LOGIN', style: TextStyle(color: Colors.white, fontSize: 18)))),
                    SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Don't have an account? "), Text('Sign up', style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.bold))]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== HOME NA TABS ZAKO ZOTE =====
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SkyNest'), backgroundColor: Color(0xFFD4A017), foregroundColor: Colors.white),
      body: Center(child: Text('Welcome - App yako iko sawa sasa!')),
    );
  }
}
