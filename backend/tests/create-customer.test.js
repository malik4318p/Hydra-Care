import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  applicationUserInsert,
  authCreateAttributes,
  createCustomerAccount,
} from '../../supabase/functions/create-customer/create-customer.js';

const adminAuthId = '11111111-1111-4111-8111-111111111111';
const createdAuthId = '22222222-2222-4222-8222-222222222222';
const token = 'Bearer supabase-access-token';
const password = 'secret-12';

function payload(overrides = {}) {
  return {
    name: 'New Customer',
    phone: '5551112222',
    email: 'new@integration.hydra-care.test',
    password,
    address: '12 Test Road',
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
    async emailTaken() {
      calls.push(['emailTaken']);
      return false;
    },
    async createAuthUser(email, plainPassword) {
      calls.push(['createAuthUser', email, plainPassword]);
      return { id: createdAuthId, email };
    },
    async insertApplicationUser(row) {
      calls.push(['insertApplicationUser', row]);
      return {
        id: 9,
        name: row.name,
        phone: row.phone,
        email: row.email,
        authUserId: row.auth_user_id,
      };
    },
    async insertCustomer(row) {
      calls.push(['insertCustomer', row]);
      return {
        id: 4,
        address: row.address,
        createdAt: '2026-09-30T00:00:00.000Z',
        updatedAt: '2026-09-30T00:00:00.000Z',
      };
    },
    async deleteApplicationUser(userId) {
      calls.push(['deleteApplicationUser', userId]);
    },
    async deleteAuthUser(authUserId) {
      calls.push(['deleteAuthUser', authUserId]);
    },
    ...overrides,
  };
  return fake;
}

function names(fake) {
  return fake.calls.map((call) => call[0]);
}

describe('create-customer', () => {
  it('creates the Auth password and stores no bcrypt hash on public.users', async () => {
    const fake = gateway();
    const result = await createCustomerAccount({
      authorization: token,
      payload: payload(),
      gateway: fake,
    });

    assert.equal(result.status, 201);
    assert.equal(result.body.data.email, 'new@integration.hydra-care.test');
    assert.equal(result.body.data.role, 'customer');
    assert.equal(result.body.data.user_id, 9);
    assert.equal(Object.hasOwn(result.body.data, 'password'), false);
    assert.equal(Object.hasOwn(result.body.data, 'password_hash'), false);

    const authCall = fake.calls.find((call) => call[0] === 'createAuthUser');
    assert.deepEqual(authCall, ['createAuthUser', 'new@integration.hydra-care.test', password]);

    const insert = fake.calls.find((call) => call[0] === 'insertApplicationUser')[1];
    assert.equal(insert.password_hash, null);
    assert.equal(insert.auth_user_id, createdAuthId);
    assert.equal(insert.role, 'customer');
    assert.equal(Object.hasOwn(insert, 'password'), false);
    assert.equal(names(fake).includes('deleteAuthUser'), false);
  });

  it('rejects a non-admin before creating an Auth user', async () => {
    const fake = gateway({
      async applicationUserByAuthId() {
        return { id: 2, role: 'customer' };
      },
    });
    const result = await createCustomerAccount({
      authorization: token,
      payload: payload(),
      gateway: fake,
    });

    assert.equal(result.status, 403);
    assert.equal(names(fake).includes('createAuthUser'), false);
    assert.equal(names(fake).includes('insertApplicationUser'), false);
  });

  it('rejects an email that already exists before creating an Auth user', async () => {
    const fake = gateway({
      async emailTaken() {
        fake.calls.push(['emailTaken']);
        return true;
      },
    });
    const result = await createCustomerAccount({
      authorization: token,
      payload: payload(),
      gateway: fake,
    });

    assert.equal(result.status, 409);
    assert.equal(result.body.message, 'A user with this email already exists');
    assert.equal(names(fake).includes('createAuthUser'), false);
  });

  it('deletes the Auth user when the application insert fails', async () => {
    const fake = gateway({
      async insertApplicationUser() {
        fake.calls.push(['insertApplicationUser']);
        const error = new Error('null value in column "password_hash"');
        error.code = '23502';
        throw error;
      },
    });
    const result = await createCustomerAccount({
      authorization: token,
      payload: payload(),
      gateway: fake,
    });

    assert.equal(result.status, 400);
    assert.equal(result.body.success, false);
    assert.deepEqual(
      fake.calls.filter((call) => call[0] === 'deleteAuthUser'),
      [['deleteAuthUser', createdAuthId]]
    );
    assert.equal(names(fake).includes('insertCustomer'), false);
  });

  it('builds an Auth admin payload with password and without password_hash', () => {
    const attributes = authCreateAttributes('new@integration.hydra-care.test', password);
    assert.deepEqual(attributes, {
      email: 'new@integration.hydra-care.test',
      password,
      email_confirm: true,
    });
    assert.equal(Object.hasOwn(attributes, 'password_hash'), false);

    const row = applicationUserInsert({
      name: 'New Customer',
      phone: '5551112222',
      email: 'new@integration.hydra-care.test',
      authUserId: createdAuthId,
    });
    assert.equal(row.password_hash, null);
    assert.equal(row.password_hash?.startsWith?.('$2'), undefined);
  });

  it('leaves Express customer creation on bcrypt', () => {
    const root = fileURLToPath(new URL('../..', import.meta.url));
    const customerService = readFileSync(`${root}/backend/src/services/customerService.js`, 'utf8');
    const adminService = readFileSync(`${root}/mobile/lib/services/admin_service.dart`, 'utf8');
    const migration = readFileSync(
      `${root}/backend/database/migrations/006_nullable_password_hash.sql`,
      'utf8'
    );
    const createStart = adminService.indexOf('Future<Customer> createCustomer');
    const createBody = adminService.slice(createStart, adminService.indexOf('Future<Customer> updateCustomer'));

    assert.match(customerService, /bcrypt\.hash\(password, SALT_ROUNDS\)/);
    assert.match(customerService, /INSERT INTO users \(name, phone, email, password_hash, role\)/);
    assert.doesNotMatch(createBody, /_apiClient\.post\(\s*'\/customers'/);
    assert.match(createBody, /_accounts\.createCustomer/);
    assert.match(migration, /ALTER COLUMN password_hash DROP NOT NULL/);
    assert.doesNotMatch(migration, /UPDATE|INSERT|\$2[aby]/);
  });
});
