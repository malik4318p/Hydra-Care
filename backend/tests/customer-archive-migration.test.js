import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function read(relativePath) {
  return readFileSync(`${root}/${relativePath}`, 'utf8');
}

describe('customer archive migration content', () => {
  const migration = read('backend/database/migrations/008_customer_archive.sql');

  it('adds customers.active with a TRUE default and does not delete anything', () => {
    assert.match(
      migration,
      /ALTER TABLE public\.customers\s+ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;/
    );
    assert.doesNotMatch(migration, /\bDELETE\s+FROM\b/i);
    assert.doesNotMatch(migration, /DROP TABLE/i);
    assert.doesNotMatch(migration, /DROP COLUMN/i);
  });

  it('does not touch products, users, or any authentication table', () => {
    assert.doesNotMatch(migration, /ALTER TABLE public\.products/i);
    assert.doesNotMatch(migration, /ALTER TABLE public\.users/i);
    assert.doesNotMatch(migration, /ALTER TABLE auth\./i);
    assert.doesNotMatch(migration, /auth\.users/i);
  });

  it('reuses the existing admin UPDATE policy instead of creating a new one', () => {
    assert.doesNotMatch(migration, /CREATE POLICY/i);
    assert.match(migration, /GRANT UPDATE \(active\) ON public\.customers TO authenticated;/);
    assert.match(migration, /GRANT SELECT \(active\) ON public\.customers TO authenticated;/);
  });

  it('adds a BEFORE INSERT trigger on transactions only, not on payments or as an UPDATE trigger', () => {
    assert.match(migration, /BEFORE INSERT ON public\.transactions/);
    assert.doesNotMatch(migration, /CREATE TRIGGER trg_payments_block_archived_customer/);
    assert.doesNotMatch(migration, /BEFORE INSERT ON public\.payments/);
    assert.doesNotMatch(migration, /BEFORE UPDATE ON public\.(transactions|payments)/);
    assert.match(migration, /SECURITY DEFINER/);
    assert.match(migration, /SET search_path = pg_catalog, public/);
  });

  it('redefines create_transaction with an archived-customer guard, create_payment without one, and leaves update_* alone', () => {
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.create_transaction/);
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.create_payment/);
    assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.update_transaction/);
    assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.update_payment/);
    assert.match(migration, /cannot be used for a new sale/);
    assert.doesNotMatch(migration, /cannot be used for a new payment/);

    const createPaymentStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.create_payment');
    const createPaymentEnd = migration.indexOf('$$;', createPaymentStart);
    const createPaymentBody = migration.slice(createPaymentStart, createPaymentEnd);
    assert.doesNotMatch(createPaymentBody, /v_customer_active/);
    assert.match(createPaymentBody, /IF NOT EXISTS \(SELECT 1 FROM public\.customers WHERE id = customer_id\) THEN/);
  });

  it('keeps the RPC grants scoped to authenticated only', () => {
    assert.match(
      migration,
      /REVOKE ALL ON FUNCTION public\.create_transaction\(integer, integer, integer, numeric, text\) FROM PUBLIC, anon;/
    );
    assert.match(
      migration,
      /GRANT EXECUTE ON FUNCTION public\.create_transaction\(integer, integer, integer, numeric, text\) TO authenticated;/
    );
  });

  it('does not apply the migration automatically', () => {
    assert.match(migration, /This file is not executed automatically/);
  });
});

describe('customer archive Flutter source', () => {
  const customerModel = read('mobile/lib/models/customer.dart');
  const dataService = read('mobile/lib/services/customer_data_service.dart');
  const adminService = read('mobile/lib/services/admin_service.dart');
  const customersScreen = read('mobile/lib/features/admin/screens/customers_screen.dart');
  const transactionsScreen = read('mobile/lib/features/admin/screens/transactions_screen.dart');
  const paymentsScreen = read('mobile/lib/features/admin/screens/payments_screen.dart');

  it('Customer model has an active field defaulting to true when absent', () => {
    assert.match(customerModel, /final bool active;/);
    assert.match(customerModel, /active: json\['active'\] as bool\? \?\? true/);
  });

  it('listCustomers supports an active filter and a search term', () => {
    assert.match(
      dataService,
      /Future<List<Customer>> listCustomers\(\{bool\? activeOnly, String\? search\}\)/
    );
    assert.match(dataService, /query\.eq\('active', activeOnly\)/);
    assert.match(dataService, /referencedTable: 'users'/);
    assert.match(dataService, /users!fk_customers_user!inner/);
  });

  it('provides archive and restore methods that update only customers.active', () => {
    assert.match(dataService, /Future<void> archiveCustomer\(int id\)/);
    assert.match(dataService, /Future<void> restoreCustomer\(int id\)/);
    assert.match(dataService, /\.update\(\{'active': active\}\)/);
    assert.doesNotMatch(dataService, /\.delete\(\)/);
    assert.match(adminService, /Future<void> archiveCustomer\(int id\)/);
    assert.match(adminService, /Future<void> restoreCustomer\(int id\)/);
  });

  it('Customers screen has an Active/Archived filter, search field, and archive confirmation', () => {
    assert.match(customersScreen, /SegmentedButton<bool>/);
    assert.match(customersScreen, /SearchField/);
    assert.match(customersScreen, /Archive this customer\?/);
    assert.match(customersScreen, /widget\.adminService\.archiveCustomer/);
    assert.match(customersScreen, /widget\.adminService\.restoreCustomer/);
    assert.match(customersScreen, /_ArchivedBadge/);
  });

  it('transaction creation only offers active customers; payment creation offers active and archived, clearly marked', () => {
    const createTransactionStart = transactionsScreen.indexOf('_CreateTransactionScreen');
    const createTransactionBody = transactionsScreen.slice(createTransactionStart);
    assert.match(createTransactionBody, /listCustomers\(activeOnly: true\)/);

    const createPaymentStart = paymentsScreen.indexOf('_CreatePaymentScreen');
    const createPaymentBody = paymentsScreen.slice(createPaymentStart);
    assert.doesNotMatch(createPaymentBody, /listCustomers\(activeOnly: true\)/);
    assert.match(createPaymentBody, /widget\.adminService\.listCustomers\(\)/);
    assert.match(createPaymentBody, /\(Archived\)/);
  });

  it('Transactions and payments list screens have a customer search field', () => {
    assert.match(transactionsScreen, /SearchField/);
    assert.match(transactionsScreen, /_filteredTransactions/);
    assert.match(paymentsScreen, /SearchField/);
    assert.match(paymentsScreen, /_filteredPayments/);
  });

  it('payments list search can find archived customers; default customers list is active-only', () => {
    const paymentsListBody = paymentsScreen.slice(0, paymentsScreen.indexOf('_CreatePaymentScreen'));
    assert.match(paymentsListBody, /widget\.adminService\.listCustomers\(\)/);
    assert.doesNotMatch(paymentsListBody, /activeOnly/);

    assert.match(customersScreen, /bool _showArchived = false;/);
    assert.match(customersScreen, /activeOnly: !_showArchived/);
  });

  it('does not introduce any Express/API call for the archive or search feature', () => {
    assert.doesNotMatch(dataService, /ApiClient|http\.(get|post|put|delete)/);
    assert.doesNotMatch(customersScreen, /ApiClient|http\.(get|post|put|delete)/);
  });
});
