import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MissingConfig());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  final s = await Services.init();
  await s.session.start();
  // Deliver any bookings made while offline last time.
  s.orders.flushQueue().ignore();

  runApp(MukhtabaratApp(services: s));
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Missing configuration.\n\nRun with:\nflutter run --dart-define-from-file=config/dev.json\n\n'
                'See config/example.json.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
