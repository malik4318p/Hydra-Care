import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

describe('customer name and phone update', () => {
  it('updates name and phone in Supabase and leaves Express customer update intact', () => {
    const root = fileURLToPath(new URL('../..', import.meta.url));
    const adminService = readFileSync(`${root}/mobile/lib/services/admin_service.dart`, 'utf8');
    const dataService = readFileSync(`${root}/mobile/lib/services/customer_data_service.dart`, 'utf8');
    const customerService = readFileSync(`${root}/backend/src/services/customerService.js`, 'utf8');
    const migration = readFileSync(
      `${root}/backend/database/migrations/007_customer_name_phone_update.sql`,
      'utf8'
    );

    const updateStart = adminService.indexOf('Future<Customer> updateCustomer');
    const updateBody = adminService.slice(updateStart, adminService.indexOf('Future<List<Product>> listProducts'));
    const profileStart = dataService.indexOf('Future<void> updateNameAndPhone');
    const profileBody = dataService.slice(profileStart, dataService.indexOf('Future<Customer> updateAddress'));

    assert.match(updateBody, /updateNameAndPhone\(id: id, name: name, phone: phone\)/);
    assert.match(updateBody, /changeCustomerEmail/);
    assert.match(updateBody, /updateAddress\(id: id, address: address\)/);
    assert.doesNotMatch(updateBody, /_apiClient/);

    assert.match(profileBody, /from\('users'\)/);
    assert.match(profileBody, /'name': trimmedName/);
    assert.match(profileBody, /'phone': trimmedPhone/);
    assert.doesNotMatch(profileBody, /'email'|password_hash|auth_user_id/);

    assert.match(customerService, /name = COALESCE\(\$1, name\)/);
    assert.match(customerService, /phone = COALESCE\(\$2, phone\)/);
    const grant = migration
      .split('\n')
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n');
    assert.match(grant, /GRANT UPDATE \(name, phone\) ON public\.users TO authenticated/);
    assert.match(grant, /private\.is_admin\(\) AND role = 'customer'/);
    assert.doesNotMatch(grant, /email|password_hash|auth_user_id|auth\.users/);
  });
});
