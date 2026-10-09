import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  authEmailUpdate,
  changeCustomerEmail,
  mapAuthUpdateError,
} from '../../supabase/functions/update-customer-email/email-change.js';

const adminAuthId = '11111111-1111-4111-8111-111111111111';
const customerAuthId = '22222222-2222-4222-8222-222222222222';
const token = 'Bearer supabase-access-token';

function target(overrides = {}) {
  return {
    customerId: 7,
    userId: 9,
    email: 'customer@integration.hydra-care.test',
    role: 'customer',
    authUserId: customerAuthId,
    ...overrides,
  };
}

function gateway(overrides = {}) {
  const calls = [];
  const fake = {
    calls,
    async verifiedUserId() {
      calls.push(['verifiedUserId']);
      return adminAuthId;
    },
    async applicationUserByAuthId() {
      calls.push(['applicationUserByAuthId']);
      return { id: 1, role: 'admin' };
    },
    async customerAccount() {
      calls.push(['customerAccount']);
      return target();
    },
    async authUser() {
      calls.push(['authUser']);
      return { id: customerAuthId, email: 'customer@integration.hydra-care.test' };
    },
    async emailTaken() {
      calls.push(['emailTaken']);
      return false;
    },
    async updateAuthEmail(authUserId, email) {
      calls.push(['updateAuthEmail', authUserId, email]);
      return { email };
    },
    async publicEmail() {
      calls.push(['publicEmail']);
      return 'next@integration.hydra-care.test';
    },
    ...overrides,
  };
  return fake;
}

function names(fake) {
  return fake.calls.map((call) => call[0]);
}

describe('update-customer-email', () => {
  it('lets an admin change a customer email and leaves the auth link unchanged', async () => {
    let storedEmail = 'customer@integration.hydra-care.test';
    const fake = gateway({
      async customerAccount() {
        fake.calls.push(['customerAccount']);
        return target({ email: storedEmail });
      },
      async updateAuthEmail(authUserId, email) {
        fake.calls.push(['updateAuthEmail', authUserId, email]);
        storedEmail = email;
        return { email };
      },
      async publicEmail() {
        fake.calls.push(['publicEmail']);
        return storedEmail;
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'next@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 200);
    assert.equal(result.body.success, true);
    assert.equal(result.body.data.email, 'next@integration.hydra-care.test');
    assert.equal(result.body.data.auth_user_id, customerAuthId);
    assert.equal(result.body.data.unchanged, false);
    assert.deepEqual(
      fake.calls.filter((call) => call[0] === 'updateAuthEmail'),
      [['updateAuthEmail', customerAuthId, 'next@integration.hydra-care.test']]
    );
  });

  it('rejects a non-admin before any Auth update', async () => {
    const fake = gateway({
      async applicationUserByAuthId() {
        return { id: 2, role: 'customer' };
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'next@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 403);
    assert.equal(result.body.message, 'You do not have permission to perform this action');
    assert.equal(names(fake).includes('updateAuthEmail'), false);
    assert.equal(names(fake).includes('customerAccount'), false);
  });

  it('does not call Auth when the requested email is already current', async () => {
    const fake = gateway();
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'customer@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 200);
    assert.equal(result.body.data.unchanged, true);
    assert.equal(result.body.data.auth_user_id, customerAuthId);
    assert.equal(names(fake).includes('updateAuthEmail'), false);
    assert.equal(names(fake).includes('emailTaken'), false);
  });

  it('rejects an email that another application user already has', async () => {
    const fake = gateway({
      async emailTaken() {
        fake.calls.push(['emailTaken']);
        return true;
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'taken@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 409);
    assert.equal(result.body.message, 'A user with this email already exists');
    assert.equal(names(fake).includes('updateAuthEmail'), false);
  });

  it('does not report success when the Auth update fails', async () => {
    const fake = gateway({
      async updateAuthEmail() {
        fake.calls.push(['updateAuthEmail']);
        const error = new Error('A user with this email address has already been registered');
        error.status = 422;
        error.code = 'email_exists';
        throw error;
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'next@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 409);
    assert.equal(result.body.success, false);
    assert.equal(names(fake).includes('publicEmail'), false);
  });

  it('reverts Auth and reports failure when public.users does not receive the new email', async () => {
    const fake = gateway({
      async publicEmail() {
        fake.calls.push(['publicEmail']);
        return 'customer@integration.hydra-care.test';
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'next@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 500);
    assert.equal(result.body.success, false);
    assert.equal(result.body.message, 'The email could not be synchronized.');
    assert.deepEqual(
      fake.calls.filter((call) => call[0] === 'updateAuthEmail'),
      [
        ['updateAuthEmail', customerAuthId, 'next@integration.hydra-care.test'],
        ['updateAuthEmail', customerAuthId, 'customer@integration.hydra-care.test'],
      ]
    );
  });

  it('rejects a customer who is not linked to Auth', async () => {
    const fake = gateway({
      async customerAccount() {
        return target({ authUserId: null });
      },
    });
    const result = await changeCustomerEmail({
      authorization: token,
      payload: { customer_id: 7, email: 'next@integration.hydra-care.test' },
      gateway: fake,
    });

    assert.equal(result.status, 400);
    assert.equal(result.body.message, 'This customer is not linked to a sign-in account.');
    assert.equal(names(fake).includes('updateAuthEmail'), false);
  });

  it('sends only the email attribute to Auth', () => {
    assert.deepEqual(authEmailUpdate('next@integration.hydra-care.test'), {
      email: 'next@integration.hydra-care.test',
    });
    assert.equal(Object.hasOwn(authEmailUpdate('next@integration.hydra-care.test'), 'password'), false);
  });

  it('maps a duplicate Auth email to the existing conflict message', () => {
    const mapped = mapAuthUpdateError({
      message: 'A user with this email address has already been registered',
      code: 'email_exists',
      status: 422,
    });
    assert.deepEqual(mapped, {
      status: 409,
      message: 'A user with this email already exists',
    });
  });

  it('keeps Express login and the Express customer update available', () => {
    const root = fileURLToPath(new URL('../..', import.meta.url));
    const authRoutes = readFileSync(`${root}/backend/src/routes/authRoutes.js`, 'utf8');
    const customerService = readFileSync(`${root}/backend/src/services/customerService.js`, 'utf8');
    const adminService = readFileSync(`${root}/mobile/lib/services/admin_service.dart`, 'utf8');
    const migration = readFileSync(
      `${root}/backend/database/migrations/005_auth_email_sync.sql`,
      'utf8'
    );

    assert.match(authRoutes, /router\.post\('\/login'/);
    assert.match(authRoutes, /router\.post\('\/supabase-login'/);
    assert.match(customerService, /email = COALESCE\(\$3, email\)/);
    const updateStart = adminService.indexOf('Future<Customer> updateCustomer');
    const updateBody = adminService.slice(updateStart, adminService.indexOf('Future<List<Product>> listProducts'));
    assert.doesNotMatch(updateBody, /_apiClient\.put/);
    assert.match(updateBody, /updateNameAndPhone\(id: id, name: name, phone: phone\)/);
    assert.doesNotMatch(updateBody, /'email': email/);
    assert.match(updateBody, /updateAddress\(id: id, address: address\)/);
    assert.match(updateBody, /currentEmail != email/);
    assert.match(migration, /SET email = NEW\.email/);
    assert.match(migration, /SECURITY DEFINER/);
    assert.match(migration, /SET search_path = pg_catalog, public/);
    assert.doesNotMatch(migration, /GRANT .+ ON (TABLE )?auth\.users/i);
    assert.doesNotMatch(migration, /password_hash/);
    assert.match(migration, /CREATE TRIGGER trg_auth_user_email_sync/);
  });
});
