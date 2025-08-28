// lib/screens/subscription.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../constants/text.dart';
import '../services/stripe_data.dart'; // FetchStripeData() / StripeData
import '../services/chechout_page.dart'; // CheckOutPage widget (your webview)

enum CheckoutState { idle, processing, success, error }

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<StripeData> _stripeDataFuture;
  CheckoutState _starterState = CheckoutState.idle;
  CheckoutState _proState = CheckoutState.idle;

  @override
  void initState() {
    super.initState();
    _stripeDataFuture = FetchStripeData();
  }

  /// Core checkout flow:
  /// 1) create /users/{uid}/checkout_sessions doc (server/cloud function watches this and creates a Stripe session and writes `url` + `sessionId`)
  /// 2) wait for the backend to write `url` into the doc
  /// 3) open webview with the url
  /// 4) optionally (and importantly) listen to the checkout_sessions doc for status updates (webhook will set status to 'complete'/'active')
  Future<void> _startCheckoutFlow({
    required String priceId,
    required void Function(CheckoutState) setStateCallback,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to subscribe.')),
      );
      return;
    }

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    setStateCallback(CheckoutState.processing);

    DocumentReference<Map<String, dynamic>>? docRef;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? statusSub;

    try {
      // 1) create the checkout_sessions doc (cloud function/server should react to this)
      docRef = await firestore.collection('users').doc(uid).collection('checkout_sessions').add({
        'price': priceId,
        'success_url': 'https://success.com',
        'cancel_url': 'https://cancel.com',
        'status': 'created', // initial state
        'created': FieldValue.serverTimestamp(),
      });

      // 2) wait for the backend to provide a checkout url (or error status)
      final snapshot = await docRef.snapshots().firstWhere((snap) {
        final data = snap.data();
        return data != null && (data['url'] != null || data['status'] == 'error');
      }).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('Timed out waiting for checkout url'),
      );

      if (!mounted) return;

      final data = snapshot.data();
      if (data == null) throw Exception('Checkout doc missing data');

      if (data['status'] == 'error') {
        throw Exception('Checkout creation failed on server');
      }

      final url = (data['url'] as String?)?.trim();
      if (url == null || url.isEmpty) throw Exception('No checkout url provided');

      // Start listening for final status updates (webhook -> firestore)
      statusSub = docRef.snapshots().listen((snap) {
        final d = snap.data();
        if (d == null) return;
        final status = (d['status'] as String?)?.toLowerCase() ?? '';

        if (status == 'complete' || status == 'completed' || status == 'active') {
          // server confirmed checkout -> subscription is active
          setStateCallback(CheckoutState.success);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subscription activated (server confirmed).')),
          );
          // cancel the listener after detection
          statusSub?.cancel();
        } else if (status == 'error') {
          setStateCallback(CheckoutState.error);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subscription failed (server error).')),
          );
          statusSub?.cancel();
        }
      });

      // 3) open webview page and await the result ('success' or 'cancel')
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CheckOutPage(url: url)),
      );

      if (!mounted) return;

      // 4) react to webview result (user completed checkout in Stripe domain)
      if (result == 'success') {
        // UI change; still rely on server webhook to mark the doc active.
        // Keep the listener active for the webhook to mark the doc 'active'.
        setStateCallback(CheckoutState.success);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Browser reported success — waiting for server confirmation.')),
        );
        // We allow the statusSub to detect final active/complete, or just return to idle
      } else if (result == 'cancel') {
        setStateCallback(CheckoutState.idle);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription cancelled.')));
        // cancel listener to avoid waiting forever
        await statusSub?.cancel();
      } else {
        // unknown result - leave state as idle
        setStateCallback(CheckoutState.idle);
        await statusSub?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setStateCallback(CheckoutState.error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checkout failed: ${e.toString()}')));
      // give user a moment then return to idle
      await Future.delayed(const Duration(seconds: 1));
      setStateCallback(CheckoutState.idle);
    } finally {
      try {
        await statusSub?.cancel();
      } catch (_) {}
    }
  }

  Widget _buttonChild(CheckoutState state, String label) {
    if (state == CheckoutState.processing) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    return Text(
      label,
      style: AppText.bodyText.copyWith(color: AppColors.white, fontSize: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(color: AppColors.black),
          title: Text('Subscription', style: AppText.heading2),
          backgroundColor: AppColors.white,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: AppColors.blue,
            labelColor: AppColors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Starter'),
              Tab(text: 'Pro'),
            ],
          ),
        ),
        body: FutureBuilder<StripeData>(
          future: _stripeDataFuture,
          builder: (context, snapshot) {
            final stripeData = snapshot.data;
            return TabBarView(
              children: [
                // Starter: $7 / month
                _PlanView(
                  title: 'Starter',
                  price: '7',
                  period: '/ month',
                  features: const [
                    'Basic features',
                    'Limited support',
                    'Single device',
                  ],
                  buttonText:
                  _starterState == CheckoutState.processing ? 'Processing...' : 'Choose Starter',
                  onPressed: _starterState == CheckoutState.processing
                      ? null
                      : () async {
                    final priceId = stripeData?.subprice1ID ?? '';
                    if (priceId.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starter price not configured.')),
                      );
                      return;
                    }
                    await _startCheckoutFlow(
                      priceId: priceId,
                      setStateCallback: (s) => setState(() => _starterState = s),
                    );
                  },
                  upgradeChild: _buttonChild(_starterState, 'Choose Starter'),
                ),

                // Pro: $74 / year
                _PlanView(
                  title: 'Pro',
                  price: '74',
                  period: '/ year',
                  features: const [
                    'All Starter features',
                    'Priority support',
                    'Multi-device',
                    'Advanced analytics',
                  ],
                  buttonText: _proState == CheckoutState.processing ? 'Processing...' : 'Choose Pro',
                  onPressed: _proState == CheckoutState.processing
                      ? null
                      : () async {
                    final priceId = stripeData?.subprice2ID ?? '';
                    if (priceId.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pro price not configured.')),
                      );
                      return;
                    }
                    await _startCheckoutFlow(
                      priceId: priceId,
                      setStateCallback: (s) => setState(() => _proState = s),
                    );
                  },
                  upgradeChild: _buttonChild(_proState, 'Choose Pro'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  final String title;
  final String price; // numeric price, e.g. '7' or '74'
  final String period; // '/ month' or '/ year'
  final List<String> features;
  final String buttonText;
  final VoidCallback? onPressed;
  final Widget? upgradeChild;

  const _PlanView({
    required this.title,
    required this.price,
    required this.period,
    required this.features,
    required this.buttonText,
    required this.onPressed,
    this.upgradeChild,
  });

  @override
  Widget build(BuildContext context) {
    final displayPrice =
    (price.toLowerCase() == '0' || price.toLowerCase() == 'free')
        ? 'Free'
        : '\$${price} $period';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: AppText.heading1)),
                ],
              ),
              const SizedBox(height: 8),
              Text(displayPrice, style: AppText.heading2.copyWith(color: AppColors.blue)),
              const SizedBox(height: 16),
              ...features.map(
                    (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Icon(Icons.check, color: AppColors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: AppText.bodyText)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: upgradeChild ??
                      Text(
                        buttonText,
                        style: AppText.bodyText.copyWith(
                          color: AppColors.white,
                          fontSize: 16,
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
