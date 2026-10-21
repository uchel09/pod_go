import 'package:drift/drift.dart';

import 'expense_categories.dart';
import 'users.dart';

/// Tabel transaksi pengeluaran operasional.
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get date => dateTime()(); // Tanggal pengeluaran
  IntColumn get categoryId => integer().references(ExpenseCategories, #id)();
  IntColumn get amount => integer()(); // Nominal Rupiah integer (> 0)
  TextColumn get note => text().nullable()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))(); // cash / transfer / other
  TextColumn get status => text().withDefault(const Constant('active'))(); // active / void
  TextColumn get voidReason => text().nullable()();
  @ReferenceName('voidedExpenses')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  @ReferenceName('createdExpenses')
  IntColumn get createdBy => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

