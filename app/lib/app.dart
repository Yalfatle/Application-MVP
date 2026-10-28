import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/services.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'data/models.dart';
import 'features/auth/join_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/name_screen.dart';
import 'features/messages/chat_screen.dart';
import 'features/patient/book_screen.dart';
import 'features/patient/lab_detail_screen.dart';
import 'features/patient/order_detail_screen.dart';
import 'features/patient/patient_home.dart';
import 'features/staff/patient_record_screen.dart';
import 'features/staff/staff_home.dart';
import 'features/staff/staff_order_screen.dart';
import 'features/super_admin/manage_lab_screen.dart';
import 'l10n/app_localizations.dart';

class MukhtabaratApp extends StatefulWidget {
  const MukhtabaratApp({super.key, required this.services});
  final Services services;

  @override
  State<MukhtabaratApp> createState() => _MukhtabaratAppState();
}

class _MukhtabaratAppState extends State<MukhtabaratApp> with WidgetsBindingObserver {
  late final GoRouter _router = _buildRouter(widget.services.session);
  Timer? _queueTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep trying to deliver offline bookings while any are waiting.
    _queueTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.services.orders.hasQueued) widget.services.orders.flushQueue().ignore();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.services.orders.flushQueue().ignore();
      widget.services.session.refreshProfile().ignore();
    }
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.services.session;
    return SessionScope(
      session: session,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appName,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          locale: session.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
        ),
      ),
    );
  }
}

GoRouter _buildRouter(Session session) => GoRouter(
      refreshListenable: session,
      initialLocation: '/',
      redirect: (context, state) {
        final path = state.matchedLocation;
        if (path == '/join') return null; // invite links work signed in or not
        if (!session.isSignedIn) return path == '/login' ? null : '/login';
        if (path == '/login') return '/';
        if (session.needsName && session.role == UserRole.patient) {
          return path == '/name' ? null : '/name';
        }
        if (path == '/name' && !session.needsName) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/name', builder: (_, _) => const NameScreen()),
        GoRoute(
          path: '/join',
          builder: (_, state) => JoinScreen(token: state.uri.queryParameters['token'] ?? ''),
        ),
        GoRoute(
          path: '/',
          builder: (context, _) {
            final role = SessionScope.of(context).role;
            return role.isStaff || role == UserRole.superAdmin ? const StaffHome() : const PatientHome();
          },
        ),
        // Patient
        GoRoute(path: '/lab/:id', builder: (_, s) => LabDetailScreen(labId: s.pathParameters['id']!)),
        GoRoute(
          path: '/book/:labId/:packageId',
          builder: (_, s) => BookScreen(labId: s.pathParameters['labId']!, packageId: s.pathParameters['packageId']!),
        ),
        GoRoute(path: '/order/:id', builder: (_, s) => OrderDetailScreen(orderId: s.pathParameters['id']!)),
        GoRoute(
          path: '/chat/:id',
          builder: (_, s) => ChatScreen(
            conversationId: s.pathParameters['id']!,
            title: s.uri.queryParameters['title'] ?? '',
          ),
        ),
        // Staff
        GoRoute(path: '/staff/order/:id', builder: (_, s) => StaffOrderScreen(orderId: s.pathParameters['id']!)),
        GoRoute(
          path: '/staff/patient/:id',
          builder: (_, s) => PatientRecordScreen(patientId: s.pathParameters['id']!),
        ),
        GoRoute(path: '/super/lab/:id', builder: (_, s) => ManageLabScreen(labId: s.pathParameters['id']!)),
      ],
    );
