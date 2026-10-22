import 'package:drift/drift.dart';
import 'customers.dart';
import 'users.dart';

@TableIndex(name: 'customer_payments_customer_id_idx', columns: {#customerId})
@TableIndex(name: 'customer_payments_created_at_idx', columns: {#createdAt})
class CustomerPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get amount => integer()(); // Rupiah int (> 0)
  TextColumn get method => text().withDefault(const Constant('cash'))(); // cash / transfer / other
  TextColumn get note => text().nullable()();
  IntColumn get createdBy => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

