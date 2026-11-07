import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';

/// The owner signs in once per device. There is no registration and no account creation (decision D3).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: defaultDeviceLabel);

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signIn(
            email: _email.text,
            password: _password.text,
            deviceLabel: _deviceName.text,
          );
      // On success the router moves on by itself; this screen is replaced.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A notice such as "You were signed out" set by the session controller.
    final notice = ref.watch(sessionControllerProvider.select((s) => s.message));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.pagePadding * 1.5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('ShaktiKram', style: text.headlineMedium),
                      const SizedBox(height: 4),
                      const Text('Sign in with your owner account. You only do this once on this phone.'),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('email-field'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email address' : null,
                      ),
                      const SizedBox(height: AppTheme.gap),
                      TextFormField(
                        key: const Key('password-field'),
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword ? 'Show password' : 'Hide password',
                            icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      const SizedBox(height: AppTheme.gap),
                      TextFormField(
                        key: const Key('device-name-field'),
                        controller: _deviceName,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Device name',
                          helperText: 'Shown in your device list',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null || notice != null) ...[
                        const SizedBox(height: AppTheme.gap),
                        Text(
                          _error ?? notice!,
                          key: const Key('sign-in-message'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('sign-in-button'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
