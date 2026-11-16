import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _ink = Color(0xFF252733);
const _muted = Color(0xFF686D79);
const _blue = Color(0xFF3987D8);
const _green = Color(0xFF43B581);
const _purple = Color(0xFF8050C7);
const _orange = Color(0xFFF19A37);

class DashboardOverviewCard extends StatelessWidget {
  const DashboardOverviewCard({required this.userRole});
  final String userRole;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || userRole != 'landlord') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))]),
        child: Row(children: [
          const Icon(Icons.dashboard_outlined, color: _blue, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text(
            userRole == 'caretaker' ? 'Your assigned property workspace' : 'Your home and rent workspace',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 14),
          )),
        ]),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: uid).snapshots(),
      builder: (context, houses) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tenants').where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, tenants) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: uid).snapshots(),
          builder: (context, payments) {
            final houseCount = houses.hasData ? houses.data!.docs.length.toString() : '—';
            final tenantCount = tenants.hasData ? tenants.data!.docs.length.toString() : '—';
            var revenue = 0.0;
            if (payments.hasData) {
              for (final doc in payments.data!.docs) {
                final data = doc.data();
                final status = (data['status'] ?? '').toString().toLowerCase();
                if (status.contains('received') || status.contains('verified') || status == 'paid') {
                  final amount = data['amount'];
                  if (amount is num) revenue += amount.toDouble();
                }
              }
            }
            final revenueLabel = payments.hasData
                ? NumberFormat.compactCurrency(symbol: 'KSh ', decimalDigits: 1).format(revenue)
                : '—';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))]),
              child: Row(children: [
                Expanded(child: _OverviewMetric(icon: Icons.home_rounded, color: _blue, label: 'Houses', value: houseCount)),
                Container(width: 1, height: 48, color: const Color(0xFFE2E4E9)),
                Expanded(child: _OverviewMetric(icon: Icons.people_alt_rounded, color: _green, label: 'Tenants', value: tenantCount)),
                Container(width: 1, height: 48, color: const Color(0xFFE2E4E9)),
                Expanded(child: _OverviewMetric(icon: Icons.attach_money_rounded, color: _purple, label: 'Revenue', value: revenueLabel)),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircleAvatar(radius: 17, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 19)),
      const SizedBox(width: 7),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _ink, fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      ])),
    ]),
  );
}

class DashboardRecentActivity extends StatelessWidget {
  const DashboardRecentActivity({required this.userRole});
  final String userRole;

  @override
  Widget build(BuildContext context) {
    if (userRole != 'landlord') return const _ActivityEmpty(message: 'Updates for your assigned properties will appear here.');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _ActivityEmpty();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('activityLogs')
          .where('landlordId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _ActivityEmpty(message: 'Activity is not available right now.');
        if (!snapshot.hasData) return const Padding(
          padding: EdgeInsets.all(18), child: Center(child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))),
        );
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final av = a.data()['createdAt'];
            final bv = b.data()['createdAt'];
            final ad = av is Timestamp ? av.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final bd = bv is Timestamp ? bv.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          });
        final recent = docs.take(3).toList();
        if (recent.isEmpty) return const _ActivityEmpty();
        return Container(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17),
            boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: Column(children: [
            for (var i = 0; i < recent.length; i++)
              _ActivityRow(data: recent[i].data(), last: i == recent.length - 1),
          ]),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.data, required this.last});
  final Map<String, dynamic> data;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final action = (data['action'] ?? 'Account activity').toString();
    final lower = action.toLowerCase();
    final icon = lower.contains('payment') ? Icons.payments_rounded
        : lower.contains('maintenance') || lower.contains('complaint') ? Icons.build_rounded
        : lower.contains('notice') ? Icons.campaign_rounded : Icons.notifications_active_rounded;
    final color = lower.contains('payment') ? _blue
        : lower.contains('maintenance') || lower.contains('complaint') ? _orange
        : lower.contains('notice') ? _purple : _green;
    final created = data['createdAt'];
    final date = created is Timestamp ? created.toDate() : null;
    final when = date == null ? 'Recently' : DateFormat('d MMM • h:mma').format(date);
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 27, child: Column(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        if (!last) Expanded(child: Container(width: 1.5, color: const Color(0xFFD8DADF))),
      ])),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(when, style: const TextStyle(color: _muted, fontSize: 11.5)),
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(action, style: const TextStyle(color: _ink, fontSize: 14, height: 1.25))),
          ]),
        ]),
      )),
    ]));
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({this.message = 'Your recent activity will appear here.'});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
    child: Text(message, style: const TextStyle(color: _muted, fontSize: 13)),
  );
}

class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({required this.onAddHouse, required this.onCollectPayment, required this.onPostNotice});
  final VoidCallback onAddHouse;
  final VoidCallback onCollectPayment;
  final VoidCallback onPostNotice;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))]),
    child: Row(children: [
      Expanded(child: _QuickAction(icon: Icons.add_circle_outline, color: _blue, label: 'Add house', onTap: onAddHouse)),
      Expanded(child: _QuickAction(icon: Icons.payments_outlined, color: _green, label: 'Collect payment', onTap: onCollectPayment)),
      Expanded(child: _QuickAction(icon: Icons.campaign_outlined, color: _purple, label: 'Post notice', onTap: onPostNotice)),
    ]),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12), onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      child: Column(children: [
        CircleAvatar(radius: 19, backgroundColor: color.withOpacity(0.13),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _ink, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
