import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

String roleLabel(AppLocalizations t, UserRole r) => switch (r) {
      UserRole.patient => t.rolePatient,
      UserRole.clerk => t.roleClerk,
      UserRole.runner => t.roleRunner,
      UserRole.labAdmin => t.roleLabAdmin,
      UserRole.superAdmin => t.roleSuperAdmin,
    };

String statusLabel(AppLocalizations t, OrderStatus s) => switch (s) {
      OrderStatus.pending => t.statusPending,
      OrderStatus.accepted => t.statusAccepted,
      OrderStatus.refused => t.statusRefused,
      OrderStatus.onWay => t.statusOnWay,
      OrderStatus.sampleTaken => t.statusSampleTaken,
      OrderStatus.completed => t.statusCompleted,
      OrderStatus.cancelled => t.statusCancelled,
    };
