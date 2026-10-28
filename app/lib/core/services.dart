import '../data/documents_repository.dart';
import '../data/labs_repository.dart';
import '../data/messages_repository.dart';
import '../data/orders_repository.dart';
import '../data/staff_repository.dart';
import 'cache.dart';
import 'session.dart';

/// Everything screens need to reach the backend, created once at startup.
class Services {
  Services._(this.cache, this.session)
      : labs = LabsRepository(cache),
        orders = OrdersRepository(cache),
        documents = DocumentsRepository(),
        messages = MessagesRepository(),
        staff = StaffRepository();

  static late final Services instance;

  static Future<Services> init() async {
    final cache = await LocalCache.open();
    instance = Services._(cache, Session(cache));
    return instance;
  }

  final LocalCache cache;
  final Session session;
  final LabsRepository labs;
  final OrdersRepository orders;
  final DocumentsRepository documents;
  final MessagesRepository messages;
  final StaffRepository staff;
}

Services get services => Services.instance;
