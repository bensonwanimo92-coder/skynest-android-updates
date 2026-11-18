import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MyRoomScreen extends StatelessWidget {
  const MyRoomScreen({super.key, this.supportBuilder});
  final WidgetBuilder? supportBuilder;

  String _value(dynamic value, {String fallback = 'Not provided'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view your room.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My room'),
        actions: [
          if (supportBuilder != null) IconButton(
            tooltip: 'Report an issue',
            icon: const Icon(Icons.support_agent_outlined),
            onPressed: () => Navigator.push<void>(context,
              MaterialPageRoute<void>(builder: supportBuilder!)),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, profile) {
          if (profile.hasError) return const Center(child: Text('Your tenant profile could not be loaded.'));
          if (!profile.hasData) return const Center(child: CircularProgressIndicator());
          final user = profile.data?.data() ?? <String, dynamic>{};
          final houseId = user['houseId']?.toString() ?? '';
          if (houseId.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.home_work_outlined, size: 58),
                  SizedBox(height: 14),
                  Text('No room assigned yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text('Once your landlord approves a house assignment, your room details will appear here.',
                    textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('houses').doc(houseId).snapshots(),
            builder: (context, houseSnapshot) {
              if (houseSnapshot.hasError) return const Center(child: Text('Room details could not be loaded.'));
              if (!houseSnapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (!houseSnapshot.data!.exists) {
                return const Center(child: Text('Your assigned house record is not available. Contact your landlord.'));
              }
              final house = houseSnapshot.data!.data() ?? <String, dynamic>{};
              final rent = (house['rent'] as num?)?.toDouble() ?? 0;
              final scheme = Theme.of(context).colorScheme;
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.home_work_rounded, color: Colors.white, size: 38),
                      const SizedBox(height: 18),
                      const Text('YOUR HOME', style: TextStyle(color: Colors.white70, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('House ${_value(house['houseNo'], fallback: houseId)}',
                        style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(_value(house['estate'] ?? house['address'], fallback: 'Your assigned residence'),
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Card(child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Monthly rent'),
                      trailing: Text(NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0).format(rent),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Occupancy status'),
                      trailing: Text(_value(house['status'], fallback: house['isOccupied'] == true ? 'Occupied' : 'Assigned'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('Location'),
                      subtitle: Text(_value(house['address'] ?? house['estate'] ?? house['town'])),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Tenant account'),
                      subtitle: Text(_value(user['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName)),
                    ),
                  ])),
                  const SizedBox(height: 10),
                  const Text('If any of these details are incorrect, contact your landlord or submit a support request through SkyNest.',
                    style: TextStyle(height: 1.5)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
