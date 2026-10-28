// Plain data classes mirroring the database tables.
// Kept dependency-free so they're easy to cache as JSON.

enum UserRole {
  patient('patient'),
  clerk('clerk'),
  runner('runner'),
  labAdmin('lab_admin'),
  superAdmin('super_admin');

  const UserRole(this.db);
  final String db;

  static UserRole parse(String? v) =>
      UserRole.values.firstWhere((r) => r.db == v, orElse: () => UserRole.patient);

  int get rank => index;
  bool atLeast(UserRole other) => rank >= other.rank;
  bool get isStaff => this == clerk || this == runner || this == labAdmin;
}

enum OrderStatus {
  pending('pending'),
  accepted('accepted'),
  refused('refused'),
  onWay('on_way'),
  sampleTaken('sample_taken'),
  completed('completed'),
  cancelled('cancelled');

  const OrderStatus(this.db);
  final String db;

  static OrderStatus parse(String? v) =>
      OrderStatus.values.firstWhere((s) => s.db == v, orElse: () => OrderStatus.pending);

  bool get isClosed => this == refused || this == cancelled || this == completed;
  bool get isActive => this == accepted || this == onWay || this == sampleTaken;
}

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Profile {
  Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.labId,
    this.preferredLocale = 'ar',
  });

  final String id;
  final String? fullName;
  final UserRole role;
  final String? labId;
  final String preferredLocale;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        role: UserRole.parse(j['role'] as String?),
        labId: j['lab_id'] as String?,
        preferredLocale: (j['preferred_locale'] as String?) ?? 'ar',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'role': role.db,
        'lab_id': labId,
        'preferred_locale': preferredLocale,
      };
}

class Lab {
  Lab({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.descriptionEn,
    this.areaAr,
    this.areaEn,
    this.addressAr,
    this.addressEn,
    this.lat,
    this.lng,
    this.contactPhone,
    this.contactWhatsapp,
    this.contactEmail,
    this.coverPhotoPath,
    this.commissionRate,
    this.isActive = true,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String? descriptionAr;
  final String? descriptionEn;
  final String? areaAr;
  final String? areaEn;
  final String? addressAr;
  final String? addressEn;
  final double? lat;
  final double? lng;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? contactEmail;
  final String? coverPhotoPath;
  final double? commissionRate;
  final bool isActive;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;
  String? area(String locale) => locale == 'ar' ? (areaAr ?? areaEn) : (areaEn ?? areaAr);
  String? description(String locale) =>
      locale == 'ar' ? (descriptionAr ?? descriptionEn) : (descriptionEn ?? descriptionAr);

  factory Lab.fromJson(Map<String, dynamic> j) => Lab(
        id: j['id'] as String,
        nameAr: j['name_ar'] as String,
        nameEn: j['name_en'] as String,
        descriptionAr: j['description_ar'] as String?,
        descriptionEn: j['description_en'] as String?,
        areaAr: j['area_ar'] as String?,
        areaEn: j['area_en'] as String?,
        addressAr: j['address_ar'] as String?,
        addressEn: j['address_en'] as String?,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        contactPhone: j['contact_phone'] as String?,
        contactWhatsapp: j['contact_whatsapp'] as String?,
        contactEmail: j['contact_email'] as String?,
        coverPhotoPath: j['cover_photo_path'] as String?,
        commissionRate: _d(j['commission_rate']),
        isActive: (j['is_active'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        'description_ar': descriptionAr,
        'description_en': descriptionEn,
        'area_ar': areaAr,
        'area_en': areaEn,
        'address_ar': addressAr,
        'address_en': addressEn,
        'lat': lat,
        'lng': lng,
        'contact_phone': contactPhone,
        'contact_whatsapp': contactWhatsapp,
        'contact_email': contactEmail,
        'cover_photo_path': coverPhotoPath,
        'commission_rate': commissionRate,
        'is_active': isActive,
      };
}

class LabPackage {
  LabPackage({
    required this.id,
    required this.labId,
    required this.nameAr,
    required this.nameEn,
    required this.priceIqd,
    this.descriptionAr,
    this.descriptionEn,
    this.isActive = true,
    this.position = 0,
  });

  final String id;
  final String labId;
  final String nameAr;
  final String nameEn;
  final String? descriptionAr;
  final String? descriptionEn;
  final int priceIqd;
  final bool isActive;
  final int position;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;
  String? description(String locale) =>
      locale == 'ar' ? (descriptionAr ?? descriptionEn) : (descriptionEn ?? descriptionAr);

  factory LabPackage.fromJson(Map<String, dynamic> j) => LabPackage(
        id: j['id'] as String,
        labId: j['lab_id'] as String,
        nameAr: j['name_ar'] as String,
        nameEn: j['name_en'] as String,
        descriptionAr: j['description_ar'] as String?,
        descriptionEn: j['description_en'] as String?,
        priceIqd: (j['price_iqd'] as num).toInt(),
        isActive: (j['is_active'] as bool?) ?? true,
        position: (j['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'lab_id': labId,
        'name_ar': nameAr,
        'name_en': nameEn,
        'description_ar': descriptionAr,
        'description_en': descriptionEn,
        'price_iqd': priceIqd,
        'is_active': isActive,
        'position': position,
      };
}

class LabOrder {
  LabOrder({
    required this.id,
    required this.patientId,
    required this.labId,
    required this.packageNameAr,
    required this.packageNameEn,
    required this.priceIqd,
    required this.status,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.packageId,
    this.commissionIqd = 0,
    this.locationNote,
    this.runnerId,
    this.statusReason,
    this.queued = false,
  });

  final String id;
  final String patientId;
  final String labId;
  final String? packageId;
  final String packageNameAr;
  final String packageNameEn;
  final int priceIqd;
  final int commissionIqd;
  final OrderStatus status;
  final double lat;
  final double lng;
  final String? locationNote;
  final String? runnerId;
  final String? statusReason;
  final DateTime createdAt;

  /// Saved on the phone but not yet delivered (no connection).
  final bool queued;

  String packageName(String locale) => locale == 'ar' ? packageNameAr : packageNameEn;

  /// A plain Google Maps link anyone can open, app or not.
  String get mapsLink => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  String get directionsLink => 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';

  factory LabOrder.fromJson(Map<String, dynamic> j) => LabOrder(
        id: j['id'] as String,
        patientId: j['patient_id'] as String,
        labId: j['lab_id'] as String,
        packageId: j['package_id'] as String?,
        packageNameAr: j['package_name_ar'] as String,
        packageNameEn: j['package_name_en'] as String,
        priceIqd: (j['price_iqd'] as num).toInt(),
        commissionIqd: (j['commission_iqd'] as num?)?.toInt() ?? 0,
        status: OrderStatus.parse(j['status'] as String?),
        lat: _d(j['location_lat'])!,
        lng: _d(j['location_lng'])!,
        locationNote: j['location_note'] as String?,
        runnerId: j['runner_id'] as String?,
        statusReason: j['status_reason'] as String?,
        createdAt: _t(j['created_at']) ?? DateTime.now(),
        queued: (j['_queued'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'lab_id': labId,
        'package_id': packageId,
        'package_name_ar': packageNameAr,
        'package_name_en': packageNameEn,
        'price_iqd': priceIqd,
        'commission_iqd': commissionIqd,
        'status': status.db,
        'location_lat': lat,
        'location_lng': lng,
        'location_note': locationNote,
        'runner_id': runnerId,
        'status_reason': statusReason,
        'created_at': createdAt.toUtc().toIso8601String(),
        '_queued': queued,
      };
}

class OrderEvent {
  OrderEvent({required this.toStatus, required this.createdAt, this.note});
  final OrderStatus toStatus;
  final DateTime createdAt;
  final String? note;

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        toStatus: OrderStatus.parse(j['to_status'] as String?),
        createdAt: _t(j['created_at'])!,
        note: j['note'] as String?,
      );
}

class RunnerLocation {
  RunnerLocation({required this.lat, required this.lng, required this.updatedAt});
  final double lat;
  final double lng;
  final DateTime updatedAt;

  factory RunnerLocation.fromJson(Map<String, dynamic> j) => RunnerLocation(
        lat: _d(j['lat'])!,
        lng: _d(j['lng'])!,
        updatedAt: _t(j['updated_at'])!,
      );
}

class PatientDocument {
  PatientDocument({
    required this.id,
    required this.patientId,
    required this.labId,
    required this.fileName,
    required this.mimeType,
    required this.storagePath,
    required this.createdAt,
    this.orderId,
    this.title,
  });

  final String id;
  final String patientId;
  final String labId;
  final String? orderId;
  final String? title;
  final String fileName;
  final String mimeType;
  final String storagePath;
  final DateTime createdAt;

  String get displayName => (title == null || title!.trim().isEmpty) ? fileName : title!;
  bool get isPdf => mimeType == 'application/pdf';

  factory PatientDocument.fromJson(Map<String, dynamic> j) => PatientDocument(
        id: j['id'] as String,
        patientId: j['patient_id'] as String,
        labId: j['lab_id'] as String,
        orderId: j['order_id'] as String?,
        title: j['title'] as String?,
        fileName: j['file_name'] as String,
        mimeType: j['mime_type'] as String,
        storagePath: j['storage_path'] as String,
        createdAt: _t(j['created_at'])!,
      );
}

class Conversation {
  Conversation({
    required this.id,
    required this.labId,
    required this.patientId,
    required this.lastMessageAt,
  });
  final String id;
  final String labId;
  final String patientId;
  final DateTime lastMessageAt;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        labId: j['lab_id'] as String,
        patientId: j['patient_id'] as String,
        lastMessageAt: _t(j['last_message_at'])!,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.toPatient,
    required this.body,
    required this.createdAt,
    this.viaWhatsApp = false,
    this.readAt,
  });
  final String id;
  final String conversationId;
  final bool toPatient;
  final String body;
  final DateTime createdAt;
  final bool viaWhatsApp;
  final DateTime? readAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        toPatient: j['direction'] == 'to_patient',
        body: j['body'] as String,
        createdAt: _t(j['created_at'])!,
        viaWhatsApp: j['channel'] == 'whatsapp',
        readAt: _t(j['read_at']),
      );
}

class StaffMember {
  StaffMember({required this.id, required this.role, this.fullName});
  final String id;
  final String? fullName;
  final UserRole role;

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        role: UserRole.parse(j['role'] as String?),
      );
}

class StaffInvite {
  StaffInvite({
    required this.id,
    required this.role,
    required this.expiresAt,
    this.usedAt,
    this.revokedAt,
  });
  final String id;
  final UserRole role;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime? revokedAt;

  bool get isOpen => usedAt == null && revokedAt == null && expiresAt.isAfter(DateTime.now());

  factory StaffInvite.fromJson(Map<String, dynamic> j) => StaffInvite(
        id: j['id'] as String,
        role: UserRole.parse(j['role'] as String?),
        expiresAt: _t(j['expires_at'])!,
        usedAt: _t(j['used_at']),
        revokedAt: _t(j['revoked_at']),
      );
}

class EarningsRow {
  EarningsRow({
    required this.labId,
    required this.labNameEn,
    required this.labNameAr,
    required this.completedOrders,
    required this.revenueIqd,
    required this.commissionIqd,
  });
  final String labId;
  final String labNameEn;
  final String labNameAr;
  final int completedOrders;
  final int revenueIqd;
  final int commissionIqd;

  factory EarningsRow.fromJson(Map<String, dynamic> j) => EarningsRow(
        labId: j['lab_id'] as String,
        labNameEn: j['lab_name_en'] as String,
        labNameAr: j['lab_name_ar'] as String,
        completedOrders: (j['completed_orders'] as num).toInt(),
        revenueIqd: (j['revenue_iqd'] as num).toInt(),
        commissionIqd: (j['commission_iqd'] as num).toInt(),
      );
}

class AdminUserRow {
  AdminUserRow({
    required this.id,
    required this.role,
    this.fullName,
    this.labId,
    this.labNameEn,
    this.phone,
    this.email,
  });
  final String id;
  final String? fullName;
  final UserRole role;
  final String? labId;
  final String? labNameEn;
  final String? phone;
  final String? email;

  factory AdminUserRow.fromJson(Map<String, dynamic> j) => AdminUserRow(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        role: UserRole.parse(j['role'] as String?),
        labId: j['lab_id'] as String?,
        labNameEn: j['lab_name_en'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
      );
}
