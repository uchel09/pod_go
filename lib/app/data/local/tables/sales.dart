import 'package:drift/drift.dart';
import 'users.dart';

@TableIndex(name: 'sales_created_at_idx', columns: {#createdAt})
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  TextColumn get invoiceNo => text().unique()();
  @ReferenceName('salesAsCashier')
  IntColumn get cashierId => integer().references(Users, #id)();
  IntColumn get subtotal => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get discount => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get tax => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get taxRateBps => integer().nullable()(); // Snapshot tarif pajak saat checkout (basis poin, 1100 = 11%)
  TextColumn get taxMode => text().nullable()(); // 'exclusive' | 'inclusive'
  IntColumn get total => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get paid => integer().withDefault(const Constant(0))(); // Rupiah int
  IntColumn get change => integer().withDefault(const Constant(0))(); // Rupiah int
  TextColumn get status => text().withDefault(const Constant('completed'))(); // completed / void
  TextColumn get voidReason => text().nullable()();
  @ReferenceName('salesAsVoidedBy')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
