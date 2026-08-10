import 'package:drift/drift.dart';

abstract class SyncableTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('local'))();
  TextColumn get userId => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Accounts extends SyncableTable {
  TextColumn get name => text()();
  IntColumn get openingBalanceSatang => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get includeInNetWorth => boolean().withDefault(const Constant(true))();
}

class Categories extends SyncableTable {
  TextColumn get name => text()();
  BoolColumn get isEssential => boolean().withDefault(const Constant(false))();
}

class BudgetPeriods extends SyncableTable {
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get salaryTransactionId => text().nullable().unique()();
}

class Transactions extends SyncableTable {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get budgetPeriodId => text().nullable()();
  TextColumn get type => text()();
  IntColumn get amountSatang => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get transferGroupId => text().nullable()();
  TextColumn get refundOfTransactionId => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get note => text().nullable()();
}

class RecurringExpenses extends SyncableTable {
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get amountSatang => integer()();
  IntColumn get dueDay => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
}

class Installments extends SyncableTable {
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get amountSatang => integer()();
  IntColumn get dueDay => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get finalDueDate => dateTime().nullable()();
}

class CommitmentOccurrences extends SyncableTable {
  TextColumn get recurringExpenseId => text().nullable()();
  TextColumn get installmentId => text().nullable()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get plannedAmountSatang => integer()();
  TextColumn get linkedTransactionId => text().nullable().unique()();
  BoolColumn get isSkipped => boolean().withDefault(const Constant(false))();
}

class PeriodBudgets extends SyncableTable {
  TextColumn get budgetPeriodId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get budgetType => text()();
  IntColumn get amountSatang => integer()();
}

class SavingGoals extends SyncableTable {
  TextColumn get name => text()();
  IntColumn get targetSatang => integer()();
  IntColumn get monthlyTargetSatang => integer()();
  TextColumn get backingAccountId => text().nullable()();
  BoolColumn get isEmergencyFund => boolean().withDefault(const Constant(false))();
}

class SalaryProfiles extends SyncableTable {
  IntColumn get grossSalarySatang => integer()();
}

class PayrollDeductions extends SyncableTable {
  TextColumn get salaryProfileId => text()();
  TextColumn get name => text()();
  IntColumn get amountSatang => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class AppSettings extends SyncableTable {
  TextColumn get key => text().unique()();
  TextColumn get value => text()();
}

// Statement tables are intentionally local-only and do not extend SyncableTable.
class StatementImports extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get institution => text()();
  TextColumn get adapterVersion => text()();
  TextColumn get fileName => text()();
  TextColumn get fileHash => text()();
  IntColumn get openingBalanceSatang => integer().nullable()();
  IntColumn get closingBalanceSatang => integer().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get importedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class StatementRows extends Table {
  TextColumn get id => text()();
  TextColumn get statementImportId => text()();
  IntColumn get rowIndex => integer()();
  DateTimeColumn get postedDate => dateTime()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get descriptionRaw => text()();
  TextColumn get referenceNo => text().nullable()();
  TextColumn get direction => text()();
  IntColumn get amountSatang => integer()();
  IntColumn get runningBalanceSatang => integer().nullable()();
  TextColumn get rowFingerprint => text()();
  TextColumn get classification => text().withDefault(const Constant('pending'))();
  TextColumn get matchedTransactionId => text().nullable().unique()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
