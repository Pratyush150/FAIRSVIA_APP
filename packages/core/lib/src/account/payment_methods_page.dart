import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_exception.dart';
import '../trip/payments_remote_data_source.dart';
import 'widgets/async_content.dart';

/// The outcome of a real (Stripe) add-card attempt.
enum StripeCardResult {
  /// A card was tokenized + saved.
  added,

  /// The user dismissed the PaymentSheet.
  cancelled,

  /// Real Stripe isn't configured (mock gateway) — use the fallback sheet.
  unavailable,
}

/// Presents the native Stripe PaymentSheet to save a card. Implemented in the
/// app layer (rider_app) with flutter_stripe and injected via DI, so `core`
/// (and the Flutter-web admin app) never depend on the native plugin.
typedef StripeCardAdder = Future<StripeCardResult> Function(
  PaymentsRemoteDataSource payments,
);

/// List and add payment methods (`/payments/methods`). When a real Stripe
/// [StripeCardAdder] is injected it drives card entry through the native
/// PaymentSheet; otherwise (mock gateway) it falls back to a brand + last-4
/// sheet (no real PAN is ever entered or sent).
class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({
    super.key,
    required this.payments,
    this.stripeCardAdder,
  });
  final PaymentsRemoteDataSource payments;
  final StripeCardAdder? stripeCardAdder;

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  int _reloadTick = 0;
  void _reload() => setState(() => _reloadTick++);

  bool _addingStripe = false;

  Future<void> _addCard() async {
    // Prefer the real Stripe PaymentSheet when an adder is injected; fall back
    // to the mock brand + last-4 sheet when Stripe isn't configured.
    final adder = widget.stripeCardAdder;
    if (adder != null) {
      setState(() => _addingStripe = true);
      try {
        final result = await adder(widget.payments);
        if (result == StripeCardResult.added) {
          _reload();
          return;
        }
        if (result == StripeCardResult.cancelled) return;
        // StripeCardResult.unavailable → fall through to the mock sheet.
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      } finally {
        if (mounted) setState(() => _addingStripe = false);
      }
    }
    if (!mounted) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCardSheet(payments: widget.payments),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addingStripe ? null : _addCard,
        icon: _addingStripe
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Add card'),
      ),
      body: AsyncContent<List<Map<String, dynamic>>>(
        key: ValueKey(_reloadTick),
        load: widget.payments.methods,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.credit_card_off_outlined,
        emptyTitle: 'No payment methods',
        emptyMessage: 'Add a card to pay for rides.',
        builder: (context, list, _) => ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            for (final m in list)
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text(
                  '${(m['brand'] as String? ?? 'Card').toUpperCase()} '
                  '•••• ${m['last4'] ?? '____'}',
                ),
                subtitle: (m['isDefault'] == true)
                    ? const Text('Default')
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet({required this.payments});
  final PaymentsRemoteDataSource payments;

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _formKey = GlobalKey<FormState>();
  final _last4 = TextEditingController();
  String _brand = 'visa';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.payments.addMethod(brand: _brand, last4: _last4.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: AppSpacing.lg + insets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add card', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _brand,
              decoration: const InputDecoration(labelText: 'Card brand'),
              items: const [
                DropdownMenuItem(value: 'visa', child: Text('Visa')),
                DropdownMenuItem(
                    value: 'mastercard', child: Text('Mastercard')),
                DropdownMenuItem(value: 'amex', child: Text('Amex')),
                DropdownMenuItem(value: 'rupay', child: Text('RuPay')),
              ],
              onChanged: (v) => setState(() => _brand = v ?? 'visa'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _last4,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Last 4 digits',
                counterText: '',
              ),
              validator: (v) =>
                  (v ?? '').trim().length == 4 ? null : 'Enter the last 4 digits',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Add card',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
