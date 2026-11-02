import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  applicationUserInsert,
  createCustomerAccount,
} from '../../supabase/functions/create-customer/create-customer.js';

const adminAuthId = '11111111-1111-4111-8111-111111111111';
const token = 'Bearer supabase-access-token';

function payload(overrides = {}) {
  return {
    name: 'New Customer',
    phone: '5551112222',
    email: 'new@integration.hydra-care.test',
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
    async emailTaken(email) {
      calls.push(['emailTaken', email]);
      return false;
    },
    async insertApplicationUser(row) {
      calls.push(['insertApplicationUser', row]);
      return {
        id: 9,
        name: row.name,
        phone: row.phone,
        email: row.email,
        authUserId: null,
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
    ...overrides,
  };
  return fake;
}

function names(fake) {
  return fake.calls.map((call) => call[0]);
}

async function create(overrides = {}, gatewayOverrides = {}) {
  const fake = gateway(gatewayOverrides);
  const result = await createCustomerAccount({
    authorization: token,
    payload: payload(overrides),
    gateway: fake,
  });
  return { fake, result };
}

describe('create-customer', () => {
  it('creates a ledger customer with name and phone only', async () => {
    const { fake, result } = await create({ email: null, address: null });

    assert.equal(result.status, 201);
    assert.equal(result.body.data.name, 'New Customer');
    assert.equal(result.body.data.phone, '5551112222');
    assert.equal(result.body.data.email, null);
    assert.equal(result.body.data.address, null);
    assert.equal(result.body.data.auth_user_id, null);
    assert.equal(Object.hasOwn(result.body.data, 'password'), false);
    assert.equal(Object.hasOwn(result.body.data, 'password_hash'), false);

    const insert = fake.calls.find((call) => call[0] === 'insertApplicationUser')[1];
    assert.equal(insert.email, null);
    assert.equal(insert.password_hash, null);
    assert.equal(insert.auth_user_id, null);
    assert.equal(names(fake).includes('emailTaken'), false);
    assert.equal(names(fake).includes('deleteApplicationUser'), false);
  });

  it('accepts an optional valid email and address', async () => {
    const { fake, result } = await create();

    assert.equal(result.status, 201);
    assert.equal(result.body.data.email, 'new@integration.hydra-care.test');
    assert.equal(result.body.data.address, '12 Test Road');
    assert.deepEqual(
      fake.calls.find((call) => call[0] === 'emailTaken'),
      ['emailTaken', 'new@integration.hydra-care.test']
    );
  });

  it('treats missing, null, and blank optional values as null', async () => {
    const missing = payload();
    delete missing.email;
    delete missing.address;

    for (const optional of [
      missing,
      payload({ email: null, address: null }),
      payload({ email: '   ', address: '   ' }),
    ]) {
      const fake = gateway();
      const result = await createCustomerAccount({
        authorization: token,
        payload: optional,
        gateway: fake,
      });
      assert.equal(result.status, 201);
      assert.equal(result.body.data.email, null);
      assert.equal(result.body.data.address, null);
    }
  });

  it('does not create or delete an Auth user', async () => {
    const root = fileURLToPath(new URL('../..', import.meta.url));
    const source = [
      readFileSync(`${root}/supabase/functions/create-customer/index.ts`, 'utf8'),
      readFileSync(`${root}/supabase/functions/create-customer/create-customer.js`, 'utf8'),
      readFileSync(`${root}/supabase/functions/create-customer/gateway.js`, 'utf8'),
    ].join('\n');
    const { fake, result } = await create({ email: null, address: null });

    assert.equal(result.status, 201);
    assert.doesNotMatch(source, /auth\.admin\.createUser/);
    assert.doesNotMatch(source, /deleteAuthUser/);
    assert.equal(names(fake).includes('createAuthUser'), false);
    assert.equal(names(fake).includes('deleteAuthUser'), false);
  });

  it('rejects an invalid non-empty email', async () => {
    const { fake, result } = await create({ email: 'not-an-email' });

    assert.equal(result.status, 400);
    assert.equal(result.body.message, 'Enter a valid email.');
    assert.equal(names(fake).includes('emailTaken'), false);
    assert.equal(names(fake).includes('insertApplicationUser'), false);
  });

  it('rejects missing name and phone', async () => {
    for (const field of ['name', 'phone']) {
      const overrides = { [field]: '' };
      const { fake, result } = await create(overrides);

      assert.equal(result.status, 400);
      assert.equal(result.body.message, 'Name and phone are required.');
      assert.equal(names(fake).includes('insertApplicationUser'), false);
    }
  });

  it('rejects a duplicate non-null email before insertion', async () => {
    const calls = [];
    const fake = gateway({
      async emailTaken(email) {
        calls.push(email);
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
    assert.equal(names(fake).includes('insertApplicationUser'), false);
    assert.deepEqual(calls, ['new@integration.hydra-care.test']);
  });

  it('allows multiple customers with null email', async () => {
    const created = [];
    const fake = gateway({
      async insertApplicationUser(row) {
        created.push(row);
        return { id: created.length, name: row.name, phone: row.phone, email: row.email };
      },
      async insertCustomer(row) {
        return { id: row.userId, address: row.address, createdAt: null, updatedAt: null };
      },
    });

    for (const name of ['First', 'Second']) {
      const result = await createCustomerAccount({
        authorization: token,
        payload: payload({ name, email: null }),
        gateway: fake,
      });
      assert.equal(result.status, 201);
    }

    assert.equal(created.length, 2);
    assert.equal(created[0].email, null);
    assert.equal(created[1].email, null);
  });

  it('cleans up the application user when customer insertion fails', async () => {
    const { fake, result } = await create({ email: null, address: null }, {
      async insertCustomer() {
        fake.calls.push(['insertCustomer']);
        throw new Error('customer insert failed');
      },
    });

    assert.equal(result.status, 500);
    assert.deepEqual(
      fake.calls.filter((call) => call[0] === 'deleteApplicationUser'),
      [['deleteApplicationUser', 9]]
    );
    assert.equal(names(fake).includes('deleteAuthUser'), false);
  });

  it('requires an authenticated administrator', async () => {
    const fake = gateway({
      async applicationUserByAuthId() {
        return { id: 2, role: 'customer' };
      },
    });
    const result = await createCustomerAccount({
      authorization: token,
      payload: payload({ email: null }),
      gateway: fake,
    });

    assert.equal(result.status, 403);
    assert.equal(names(fake).includes('insertApplicationUser'), false);
  });

  it('builds a public user row without an Auth link or password hash', () => {
    assert.deepEqual(
      applicationUserInsert({
        name: 'New Customer',
        phone: '5551112222',
        email: null,
      }),
      {
        name: 'New Customer',
        phone: '5551112222',
        email: null,
        password_hash: null,
        role: 'customer',
        auth_user_id: null,
      }
    );
  });
});
