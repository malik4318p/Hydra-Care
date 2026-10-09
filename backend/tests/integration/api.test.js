import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { createClient } from '@supabase/supabase-js';
import app from '../../src/app.js';
import env from '../../src/config/env.js';
import pool from '../../src/db/pool.js';
import {
  cleanupTestData,
  closeServer,
  request,
  setBaseUrl,
  snapshotDatabase,
} from '../helpers.js';

const PASSWORD = 'secret-12';
const MISSING_ID = 2147483646;
const OUT_OF_RANGE_ID = 9999999999;
const runId = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

let sequence = 0;
let server;
let baseline;
let admin;
const createdAuthUserIds = [];
let customerA;
let customerB;
let product;

function nextSeq() {
  sequence += 1;
  return sequence;
}

function testEmail(label) {
  return `itest-${runId}-${label}-${nextSeq()}@integration.hydra-care.test`;
}

function suite(name, fn) {
  describe(name, { concurrency: false, timeout: 180_000 }, fn);
}

function assertStatus(response, status) {
  assert.equal(
    response.status,
    status,
    `expected ${status}, got ${response.status}: ${JSON.stringify(response.body)}`
  );
}

function assertSuccess(response, status = 200) {
  assertStatus(response, status);
  assert.equal(response.body.success, true);
  assert.equal(Object.hasOwn(response.body, 'data'), true);
}

function assertError(response, status, messageIncludes) {
  assertStatus(response, status);
  assert.equal(response.body.success, false);
  assert.equal(typeof response.body.message, 'string');
  assert.equal(response.body.stack, undefined);
  assert.equal(response.body.data, undefined);

  if (messageIncludes) {
    assert.ok(
      response.body.message.toLowerCase().includes(messageIncludes.toLowerCase()),
      `expected message to include "${messageIncludes}", got "${response.body.message}"`
    );
  }
}

function assertNoSecrets(value) {
  const json = JSON.stringify(value);
  assert.equal(json.includes('password_hash'), false);
  assert.equal(json.includes(PASSWORD), false);
}

function customerPayload(label, overrides = {}) {
  const seq = nextSeq();

  return {
    name: `Test ${label}`,
    phone: `555${String(seq).padStart(7, '0')}`.slice(0, 20),
    email: `itest-${runId}-${label}-${seq}@integration.hydra-care.test`,
    password: PASSWORD,
    address: `${label} address ${seq}`,
    ...overrides,
  };
}

async function createCustomer(label, overrides = {}) {
  const body = customerPayload(label, overrides);
  const response = await request('POST', '/api/customers', { token: admin.token, body });
  return { response, body };
}

async function createProduct(label, overrides = {}) {
  const body = {
    name: `itest-${runId}-${label}-${nextSeq()}`,
    type: 'bottle',
    current_price: 100,
    ...overrides,
  };
  const response = await request('POST', '/api/products', { token: admin.token, body });
  return { response, body };
}

async function login(email, password = PASSWORD) {
  return request('POST', '/api/auth/login', { body: { email, password } });
}

async function countRows(table, where, params) {
  const result = await pool.query(`SELECT COUNT(*)::int AS n FROM ${table} WHERE ${where}`, params);
  return result.rows[0].n;
}

suite('Express API integration', () => {
  before(async () => {
    await cleanupTestData();
    baseline = await snapshotDatabase();

    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
    setBaseUrl(`http://127.0.0.1:${server.address().port}`);

    const email = testEmail('admin');
    const passwordHash = await bcrypt.hash(PASSWORD, 4);
    const inserted = await pool.query(
      `INSERT INTO users (name, phone, email, password_hash, role)
       VALUES ($1, $2, $3, $4, 'admin')
       RETURNING id, email, role`,
      ['Integration Admin', '5550000000', email, passwordHash]
    );

    const loginResponse = await login(email);
    assertSuccess(loginResponse);

    admin = {
      id: inserted.rows[0].id,
      email,
      token: loginResponse.body.data.token,
    };

    const productResult = await createProduct('shared', { type: 'bottle', current_price: 19.99 });
    assertSuccess(productResult.response, 201);
    product = productResult.response.body.data;

    const first = await createCustomer('customer-a');
    const second = await createCustomer('customer-b');
    assertSuccess(first.response, 201);
    assertSuccess(second.response, 201);

    const firstLogin = await login(first.body.email);
    const secondLogin = await login(second.body.email);
    assertSuccess(firstLogin);
    assertSuccess(secondLogin);

    customerA = {
      ...first.response.body.data,
      email: first.body.email,
      password: PASSWORD,
      token: firstLogin.body.data.token,
    };
    customerB = {
      ...second.response.body.data,
      email: second.body.email,
      password: PASSWORD,
      token: secondLogin.body.data.token,
    };
  });

  after(async () => {
    try {
      if (createdAuthUserIds.length > 0) {
        const supabase = createClient(env.supabaseUrl, env.supabaseSecretKey, {
          auth: { autoRefreshToken: false, persistSession: false },
        });

        for (const id of createdAuthUserIds) {
          const { error } = await supabase.auth.admin.deleteUser(id);

          if (error) {
            throw new Error(`Failed to delete test Auth user ${id}`);
          }
        }
      }

      await cleanupTestData();

      if (baseline) {
        const current = await snapshotDatabase();
        assert.deepEqual(current, baseline);
      }
    } finally {
      if (server) {
        await closeServer(server);
      }

      await pool.end();
    }
  });

  suite('health and unknown routes', () => {
    it('reports that the API is running without authentication', async () => {
      const response = await request('GET', '/api/health');
      assertStatus(response, 200);
      assert.deepEqual(response.body, { success: true, message: 'API is running' });
    });

    it('returns 404 for an unknown route', async () => {
      const response = await request('GET', '/api/does-not-exist');
      assertError(response, 404, 'Route not found');
    });

    it('returns 404 when login is called with the wrong method', async () => {
      const response = await request('GET', '/api/auth/login');
      assertError(response, 404, 'Route not found');
    });

    it('returns 400 for malformed JSON', async () => {
      const response = await request('POST', '/api/auth/login', { rawBody: '{bad' });
      assertError(response, 400);
    });
  });

  suite('authentication', () => {
    const protectedRoutes = [
      ['GET', '/api/customers/me'],
      ['GET', '/api/customers/me/balance'],
      ['GET', '/api/customers/me/summary'],
      ['POST', '/api/customers'],
      ['GET', '/api/customers'],
      ['GET', '/api/customers/1'],
      ['PUT', '/api/customers/1'],
      ['DELETE', '/api/customers/1'],
      ['GET', '/api/customers/1/balance'],
      ['GET', '/api/customers/1/summary'],
      ['GET', '/api/products'],
      ['GET', '/api/products/1'],
      ['POST', '/api/products'],
      ['PUT', '/api/products/1'],
      ['DELETE', '/api/products/1'],
      ['GET', '/api/transactions'],
      ['GET', '/api/transactions/1'],
      ['POST', '/api/transactions'],
      ['PUT', '/api/transactions/1'],
      ['DELETE', '/api/transactions/1'],
      ['GET', '/api/payments'],
      ['GET', '/api/payments/1'],
      ['POST', '/api/payments'],
      ['PUT', '/api/payments/1'],
      ['DELETE', '/api/payments/1'],
    ];

    it('logs in an admin and returns a token without the password', async () => {
      const response = await login(admin.email);
      assertSuccess(response);
      assert.equal(response.body.data.user.id, admin.id);
      assert.equal(response.body.data.user.email, admin.email);
      assert.equal(response.body.data.user.role, 'admin');
      assert.equal(response.body.data.user.password, undefined);
      assert.equal(response.body.data.user.password_hash, undefined);

      const payload = jwt.verify(response.body.data.token, env.jwtSecret);
      assert.equal(payload.userId, admin.id);
      assert.equal(payload.role, 'admin');
      assert.ok(payload.exp - payload.iat >= 6 * 24 * 60 * 60);
    });

    it('logs in a customer', async () => {
      const response = await login(customerA.email);
      assertSuccess(response);
      assert.equal(response.body.data.user.id, customerA.user_id);
      assert.equal(response.body.data.user.role, 'customer');
      assertNoSecrets(response.body);
    });

    it('uses the same error for an unknown email and a wrong password', async () => {
      const unknown = await login(testEmail('missing-user'), 'whatever');
      const wrong = await login(admin.email, 'not-the-password');
      assertError(unknown, 401, 'Invalid email or password');
      assertError(wrong, 401, 'Invalid email or password');
      assert.equal(unknown.body.message, wrong.body.message);
    });

    it('rejects login payloads that fail validation', async () => {
      const cases = [
        [{}, 'email'],
        [{ email: 'not-an-email', password: 'secret-12' }, 'email'],
        [{ email: admin.email, password: '' }, 'password'],
        [{ email: admin.email }, 'password'],
        [{ email: "' OR 1=1 --", password: 'x' }, 'email'],
      ];

      for (const [body, field] of cases) {
        const response = await request('POST', '/api/auth/login', { body });
        assertError(response, 400, field);
      }
    });

    it('requires a bearer token on every protected route', async () => {
      const failures = [];

      for (const [method, path] of protectedRoutes) {
        const response = await request(method, path, method === 'GET' || method === 'DELETE' ? {} : { body: {} });

        if (response.status !== 401 || response.body.message !== 'Authentication required') {
          failures.push(`${method} ${path} -> ${response.status} ${JSON.stringify(response.body)}`);
        }
      }

      assert.deepEqual(failures, []);
    });

    it('rejects missing, malformed, expired, and tampered tokens', async () => {
      const expired = jwt.sign(
        { userId: admin.id, role: 'admin', exp: Math.floor(Date.now() / 1000) - 60 },
        env.jwtSecret
      );
      const wrongSecret = jwt.sign({ userId: admin.id, role: 'admin' }, 'definitely-not-the-secret');
      const [header, payload, signature] = admin.token.split('.');
      const tampered = `${header}.${payload.slice(0, -2)}aa.${signature}`;

      const cases = [
        ['Token', 'Authentication required'],
        ['Bearer', 'Authentication required'],
        ['bearer ' + admin.token, 'Authentication required'],
        ['Basic ' + admin.token, 'Authentication required'],
        ['Bearer ', 'Authentication required'],
        ['Bearer not-a-jwt', 'Invalid or expired token'],
        [`Bearer ${expired}`, 'Invalid or expired token'],
        [`Bearer ${wrongSecret}`, 'Invalid or expired token'],
        [`Bearer ${tampered}`, 'Invalid or expired token'],
      ];

      for (const [authorization, message] of cases) {
        const response = await request('GET', '/api/customers', {
          headers: { authorization },
        });
        assertError(response, 401, message);
      }
    });
  });

  suite('supabase login bridge', () => {
    function supabase() {
      return createClient(env.supabaseUrl, env.supabaseSecretKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
    }

    async function createAuthUser(email) {
      const { data, error } = await supabase().auth.admin.createUser({
        email,
        password: PASSWORD,
        email_confirm: true,
      });

      assert.equal(error, null);
      assert.equal(typeof data.user?.id, 'string');
      createdAuthUserIds.push(data.user.id);
      return data.user.id;
    }

    async function accessTokenFor(email) {
      const { data, error } = await supabase().auth.signInWithPassword({
        email,
        password: PASSWORD,
      });

      assert.equal(error, null);
      assert.equal(typeof data.session?.access_token, 'string');
      return data.session.access_token;
    }

    async function insertUser(email, role) {
      const passwordHash = await bcrypt.hash(PASSWORD, 4);
      const inserted = await pool.query(
        `INSERT INTO users (name, phone, email, password_hash, role)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, email, role`,
        ['Bridge User', '5550000099', email, passwordHash, role]
      );

      return inserted.rows[0];
    }

    it('rejects a missing or malformed Supabase authorization header', async () => {
      const missing = await request('POST', '/api/auth/supabase-login');
      const malformed = await request('POST', '/api/auth/supabase-login', {
        headers: { authorization: 'Bearer' },
      });
      const wrongScheme = await request('POST', '/api/auth/supabase-login', {
        headers: { authorization: 'Basic abc' },
      });

      assertError(missing, 401, 'Authentication required');
      assertError(malformed, 401, 'Authentication required');
      assertError(wrongScheme, 401, 'Authentication required');
    });

    it('rejects an invalid Supabase access token', async () => {
      const response = await request('POST', '/api/auth/supabase-login', {
        token: 'not-a-supabase-access-token',
      });

      assertError(response, 401, 'Invalid or expired token');
    });

    it('rejects an Express JWT presented as a Supabase access token', async () => {
      const response = await request('POST', '/api/auth/supabase-login', {
        token: admin.token,
      });

      assertError(response, 401, 'Invalid or expired token');
    });

    it('rejects a valid Supabase user that is not linked to public.users', async () => {
      const email = testEmail('supabase-unlinked');
      await createAuthUser(email);
      const accessToken = await accessTokenFor(email);
      const response = await request('POST', '/api/auth/supabase-login', {
        token: accessToken,
        body: { userId: admin.id, email: admin.email, role: 'admin' },
      });

      assertError(response, 401, 'No application user is linked');
    });

    it('exchanges a linked Supabase user for the existing Express session', async () => {
      const email = testEmail('supabase-linked');
      const user = await insertUser(email, 'customer');
      const authUserId = await createAuthUser(email);

      await pool.query('UPDATE users SET auth_user_id = $1 WHERE id = $2', [
        authUserId,
        user.id,
      ]);

      const accessToken = await accessTokenFor(email);
      const response = await request('POST', '/api/auth/supabase-login', {
        token: accessToken,
        body: {
          userId: admin.id,
          email: admin.email,
          role: 'admin',
          auth_user_id: authUserId,
        },
      });

      assertSuccess(response);
      assert.equal(response.body.data.user.id, user.id);
      assert.equal(response.body.data.user.name, 'Bridge User');
      assert.equal(response.body.data.user.email, email);
      assert.equal(response.body.data.user.role, 'customer');
      assert.equal(response.body.data.user.password_hash, undefined);
      assertNoSecrets(response.body);

      const payload = jwt.verify(response.body.data.token, env.jwtSecret);
      assert.equal(payload.userId, user.id);
      assert.equal(payload.role, 'customer');
      assert.ok(payload.exp - payload.iat >= 6 * 24 * 60 * 60);

      const products = await request('GET', '/api/products', {
        token: response.body.data.token,
      });
      assertSuccess(products);
    });
  });

  suite('authorization', () => {
    it('forbids customers from admin-only routes before validation', async () => {
      const adminOnly = [
        ['POST', '/api/customers', customerPayload('forbidden-customer')],
        ['GET', '/api/customers'],
        ['GET', `/api/customers/${MISSING_ID}`],
        ['PUT', `/api/customers/${MISSING_ID}`, { name: 'x' }],
        ['DELETE', `/api/customers/${MISSING_ID}`],
        ['GET', `/api/customers/${MISSING_ID}/balance`],
        ['GET', `/api/customers/${MISSING_ID}/summary`],
        ['POST', '/api/products', { name: `itest-${runId}-forbidden`, type: 'bottle', current_price: 1 }],
        ['PUT', `/api/products/${MISSING_ID}`, { name: `itest-${runId}-forbidden-rename` }],
        ['DELETE', `/api/products/${MISSING_ID}`],
        ['POST', '/api/transactions', { customer_id: customerA.id, product_id: product.id, quantity: 1 }],
        ['PUT', `/api/transactions/${MISSING_ID}`, { quantity: 1 }],
        ['DELETE', `/api/transactions/${MISSING_ID}`],
        ['POST', '/api/payments', { customer_id: customerA.id, amount: 1, payment_method: 'cash' }],
        ['PUT', `/api/payments/${MISSING_ID}`, { amount: 1 }],
        ['DELETE', `/api/payments/${MISSING_ID}`],
      ];
      const failures = [];

      for (const [method, path, body] of adminOnly) {
        const response = await request(method, path, { token: customerA.token, body });

        if (response.status !== 403) {
          failures.push(`${method} ${path} -> ${response.status} ${JSON.stringify(response.body)}`);
        }
      }

      assert.deepEqual(failures, []);
    });

    it('forbids an admin from customer self-service routes', async () => {
      for (const path of ['/api/customers/me', '/api/customers/me/balance', '/api/customers/me/summary']) {
        const response = await request('GET', path, { token: admin.token });
        assertError(response, 403, 'permission');
      }
    });

    it('lets a customer read products and only their own ledger', async () => {
      const ownTransaction = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerA.id, product_id: product.id, quantity: 1, notes: 'owned by A' },
      });
      const otherTransaction = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerB.id, product_id: product.id, quantity: 2, notes: 'owned by B' },
      });
      const ownPayment = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          transaction_id: ownTransaction.body.data.id,
          amount: 5,
          payment_method: 'cash',
        },
      });
      const otherPayment = await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: customerB.id, amount: 7, payment_method: 'cash' },
      });

      assertSuccess(ownTransaction, 201);
      assertSuccess(otherTransaction, 201);
      assertSuccess(ownPayment, 201);
      assertSuccess(otherPayment, 201);

      const products = await request('GET', '/api/products', { token: customerA.token });
      const oneProduct = await request('GET', `/api/products/${product.id}`, { token: customerA.token });
      assertSuccess(products);
      assertSuccess(oneProduct);
      assert.equal(oneProduct.body.data.id, product.id);
      assert.ok(products.body.data.some((item) => item.id === product.id));

      const transactions = await request('GET', '/api/transactions', {
        token: customerA.token,
        query: { customer_id: customerB.id },
      });
      assertSuccess(transactions);
      assert.ok(transactions.body.data.every((item) => item.customer_id === customerA.id));
      assert.ok(transactions.body.data.some((item) => item.id === ownTransaction.body.data.id));
      assert.equal(
        transactions.body.data.some((item) => item.id === otherTransaction.body.data.id),
        false
      );

      const hiddenTransaction = await request('GET', `/api/transactions/${otherTransaction.body.data.id}`, {
        token: customerA.token,
      });
      const missingTransaction = await request('GET', `/api/transactions/${MISSING_ID}`, {
        token: customerA.token,
      });
      assertError(hiddenTransaction, 404, 'Transaction not found');
      assertError(missingTransaction, 404, 'Transaction not found');

      const ownTransactionResponse = await request('GET', `/api/transactions/${ownTransaction.body.data.id}`, {
        token: customerA.token,
      });
      assertSuccess(ownTransactionResponse);
      assert.equal(ownTransactionResponse.body.data.id, ownTransaction.body.data.id);

      const payments = await request('GET', '/api/payments', {
        token: customerA.token,
        query: { customer_id: customerB.id },
      });
      assertSuccess(payments);
      assert.ok(payments.body.data.every((item) => item.customer_id === customerA.id));
      assert.equal(
        payments.body.data.some((item) => item.id === otherPayment.body.data.id),
        false
      );

      const hiddenPayment = await request('GET', `/api/payments/${otherPayment.body.data.id}`, {
        token: customerA.token,
      });
      assertError(hiddenPayment, 404, 'Payment not found');

      const profile = await request('GET', '/api/customers/me', { token: customerA.token });
      assertSuccess(profile);
      assert.equal(profile.body.data.id, customerA.id);
      assert.equal(profile.body.data.user_id, customerA.user_id);
      assertNoSecrets(profile.body);
    });

    it('returns 404 when a customer login has no customer profile', async () => {
      const email = testEmail('orphan');
      const passwordHash = await bcrypt.hash(PASSWORD, 4);
      await pool.query(
        `INSERT INTO users (name, phone, email, password_hash, role)
         VALUES ($1, $2, $3, $4, 'customer')`,
        ['Orphan Customer', '5550000001', email, passwordHash]
      );

      const loggedIn = await login(email);
      assertSuccess(loggedIn);

      for (const path of ['/api/transactions', '/api/payments', '/api/customers/me']) {
        const response = await request('GET', path, { token: loggedIn.body.data.token });
        assertError(response, 404, 'Customer profile not found');
      }

      const products = await request('GET', '/api/products', { token: loggedIn.body.data.token });
      assertSuccess(products);
    });
  });

  suite('customers', () => {
    it('creates, lists, reads, updates, and deletes a customer', async () => {
      const created = await createCustomer('crud');
      assertSuccess(created.response, 201);
      assertNoSecrets(created.response.body);
      assert.equal(created.response.body.data.name, created.body.name);
      assert.equal(created.response.body.data.email, created.body.email);
      assert.equal(created.response.body.data.phone, created.body.phone);
      assert.equal(created.response.body.data.address, created.body.address);
      assert.equal(created.response.body.data.role, 'customer');
      assert.equal(typeof created.response.body.data.id, 'number');
      assert.equal(typeof created.response.body.data.user_id, 'number');

      const loggedIn = await login(created.body.email);
      assertSuccess(loggedIn);

      const listed = await request('GET', '/api/customers', { token: admin.token });
      assertSuccess(listed);
      assert.ok(listed.body.data.some((item) => item.id === created.response.body.data.id));
      assertNoSecrets(listed.body);

      const fetched = await request('GET', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(fetched);
      assert.equal(fetched.body.data.email, created.body.email);

      const updated = await request('PUT', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
        body: { name: 'Updated Name', phone: '5551112222' },
      });
      assertSuccess(updated);
      assert.equal(updated.body.data.name, 'Updated Name');
      assert.equal(updated.body.data.phone, '5551112222');
      assert.equal(updated.body.data.email, created.body.email);
      assert.equal(updated.body.data.address, created.body.address);

      const sameEmail = await request('PUT', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
        body: { email: created.body.email },
      });
      assertSuccess(sameEmail);

      const emptyUpdate = await request('PUT', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
        body: {},
      });
      assertSuccess(emptyUpdate);
      assert.equal(emptyUpdate.body.data.name, 'Updated Name');

      const passwordIgnored = await request('PUT', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
        body: { password: 'a-different-password' },
      });
      assertSuccess(passwordIgnored);
      const stillLogsIn = await login(created.body.email, PASSWORD);
      assertSuccess(stillLogsIn);

      const removed = await request('DELETE', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removed);
      assert.equal(removed.body.data, null);

      const afterDelete = await request('GET', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assertError(afterDelete, 404, 'Customer not found');

      const loginAfterDelete = await login(created.body.email);
      assertError(loginAfterDelete, 401, 'Invalid email or password');
      assert.equal(await countRows('users', 'email = $1', [created.body.email]), 0);
    });

    it('rejects invalid customer payloads and does not insert a row', async () => {
      const cases = [
        [{ ...customerPayload('bad'), name: '' }, 'name'],
        [{ ...customerPayload('bad'), phone: '' }, 'phone'],
        [{ ...customerPayload('bad'), email: 'bad' }, 'email'],
        [{ ...customerPayload('bad'), password: 'short' }, 'password'],
        [{ ...customerPayload('bad'), address: '' }, 'address'],
      ];

      for (const [body, field] of cases) {
        const response = await request('POST', '/api/customers', { token: admin.token, body });
        assertError(response, 400, field);
        assert.equal(await countRows('users', 'email = $1', [body.email]), 0);
      }
    });

    it('rejects a duplicate email and rolls back the user insert', async () => {
      const created = await createCustomer('unique-email');
      assertSuccess(created.response, 201);

      const duplicate = await createCustomer('unique-email-copy', { email: created.body.email });
      assertError(duplicate.response, 409, 'email already exists');
      assert.equal(await countRows('users', 'email = $1', [created.body.email]), 1);
      assert.equal(await countRows('customers', 'user_id = $1', [created.response.body.data.user_id]), 1);
    });

    it('rejects a second customer whose email differs only by case', async () => {
      const created = await createCustomer('case-email');
      assertSuccess(created.response, 201);

      const duplicate = await createCustomer('case-email-upper', {
        email: created.body.email.toUpperCase(),
      });
      assertError(duplicate.response, 409, 'email already exists');
    });

    it('rejects an email change that collides with another user and keeps the original email', async () => {
      const created = await createCustomer('email-update');
      assertSuccess(created.response, 201);

      const response = await request('PUT', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
        body: { email: customerA.email },
      });
      assertError(response, 409, 'email already exists');

      const fetched = await request('GET', `/api/customers/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(fetched.body.data.email, created.body.email);
    });

    it('returns 400 for invalid ids and 404 for a missing customer', async () => {
      for (const path of [
        '/api/customers/abc',
        '/api/customers/0',
        '/api/customers/-5',
        '/api/customers/1.5',
        '/api/customers/abc/balance',
        '/api/customers/0/summary',
      ]) {
        const response = await request('GET', path, { token: admin.token });
        assertError(response, 400, 'id');
      }

      const fetched = await request('GET', `/api/customers/${MISSING_ID}`, { token: admin.token });
      const removed = await request('DELETE', `/api/customers/${MISSING_ID}`, { token: admin.token });
      const updated = await request('PUT', `/api/customers/${MISSING_ID}`, {
        token: admin.token,
        body: { name: 'Nobody' },
      });
      assertError(fetched, 404, 'Customer not found');
      assertError(removed, 404, 'Customer not found');
      assertError(updated, 404, 'Customer not found');
    });
  });

  suite('products', () => {
    it('creates, lists, filters, reads, updates, and deletes a product', async () => {
      const created = await createProduct('crud', { type: 'refill', current_price: 55.5 });
      assertSuccess(created.response, 201);
      assert.equal(created.response.body.data.name, created.body.name);
      assert.equal(created.response.body.data.type, 'refill');
      assert.equal(created.response.body.data.current_price, 55.5);
      assert.equal(created.response.body.data.active, true);
      assert.equal(typeof created.response.body.data.current_price, 'number');

      const listed = await request('GET', '/api/products', { token: customerA.token });
      assertSuccess(listed);
      assert.ok(listed.body.data.some((item) => item.id === created.response.body.data.id));

      const activeOnly = await request('GET', '/api/products', {
        token: admin.token,
        query: { active: 'true' },
      });
      assertSuccess(activeOnly);
      assert.ok(activeOnly.body.data.every((item) => item.active === true));
      assert.ok(activeOnly.body.data.some((item) => item.id === created.response.body.data.id));

      const fetched = await request('GET', `/api/products/${created.response.body.data.id}`, {
        token: customerB.token,
      });
      assertSuccess(fetched);
      assert.equal(fetched.body.data.name, created.body.name);

      const updated = await request('PUT', `/api/products/${created.response.body.data.id}`, {
        token: admin.token,
        body: { name: `itest-${runId}-renamed-${nextSeq()}`, current_price: 60, active: false },
      });
      assertSuccess(updated);
      assert.equal(updated.body.data.current_price, 60);
      assert.equal(updated.body.data.active, false);
      assert.equal(updated.body.data.type, 'refill');

      const inactive = await request('GET', '/api/products', {
        token: admin.token,
        query: { active: 'false' },
      });
      const stillActive = await request('GET', '/api/products', {
        token: admin.token,
        query: { active: 'true' },
      });
      assert.ok(inactive.body.data.some((item) => item.id === created.response.body.data.id));
      assert.equal(
        stillActive.body.data.some((item) => item.id === created.response.body.data.id),
        false
      );

      const emptyUpdate = await request('PUT', `/api/products/${created.response.body.data.id}`, {
        token: admin.token,
        body: {},
      });
      assertSuccess(emptyUpdate);
      assert.equal(emptyUpdate.body.data.active, false);
      assert.equal(emptyUpdate.body.data.current_price, 60);

      const removed = await request('DELETE', `/api/products/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removed);
      assert.equal(removed.body.data, null);

      const afterDelete = await request('GET', `/api/products/${created.response.body.data.id}`, {
        token: admin.token,
      });
      assertError(afterDelete, 404, 'Product not found');
    });

    it('rejects invalid products and unknown active filters', async () => {
      const cases = [
        [{ name: '', type: 'bottle', current_price: 10 }, 'name'],
        [{ name: `itest-${runId}-bad-type`, type: 'gallon', current_price: 10 }, 'type'],
        [{ name: `itest-${runId}-zero`, type: 'bottle', current_price: 0 }, 'current_price'],
        [{ name: `itest-${runId}-negative`, type: 'bottle', current_price: -5 }, 'current_price'],
        [{ name: `itest-${runId}-string`, type: 'bottle', current_price: '10' }, 'current_price'],
      ];

      for (const [body, field] of cases) {
        const response = await request('POST', '/api/products', { token: admin.token, body });
        assertError(response, 400, field);
      }

      const filter = await request('GET', '/api/products', {
        token: admin.token,
        query: { active: 'maybe' },
      });
      assertError(filter, 400, 'active');

      const stringBoolean = await request('PUT', `/api/products/${product.id}`, {
        token: admin.token,
        body: { active: 'false' },
      });
      assertError(stringBoolean, 400, 'active');

      const unchanged = await request('GET', `/api/products/${product.id}`, { token: admin.token });
      assert.equal(unchanged.body.data.active, true);
      assert.equal(unchanged.body.data.current_price, 19.99);
    });

    it('rejects a duplicate product name on create and update', async () => {
      const created = await createProduct('unique-name', { current_price: 12 });
      assertSuccess(created.response, 201);

      const duplicate = await createProduct('unique-name-copy', { name: created.body.name });
      assertError(duplicate.response, 409, 'name already exists');

      const other = await createProduct('other-name');
      assertSuccess(other.response, 201);

      const rename = await request('PUT', `/api/products/${other.response.body.data.id}`, {
        token: admin.token,
        body: { name: created.body.name },
      });
      assertError(rename, 409, 'name already exists');

      const fetched = await request('GET', `/api/products/${other.response.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(fetched.body.data.name, other.body.name);
    });

    it('returns 400 for an invalid product id and 404 for a missing product', async () => {
      for (const path of ['/api/products/abc', '/api/products/0', '/api/products/-2']) {
        const response = await request('GET', path, { token: admin.token });
        assertError(response, 400, 'id');
      }

      const fetched = await request('GET', `/api/products/${MISSING_ID}`, { token: admin.token });
      const updated = await request('PUT', `/api/products/${MISSING_ID}`, {
        token: admin.token,
        body: { current_price: 3 },
      });
      const removed = await request('DELETE', `/api/products/${MISSING_ID}`, { token: admin.token });
      assertError(fetched, 404, 'Product not found');
      assertError(updated, 404, 'Product not found');
      assertError(removed, 404, 'Product not found');
    });
  });

  suite('transactions', () => {
    it('stores the charged price independently of later product price changes', async () => {
      const createdProduct = await createProduct('historical-price', { current_price: 50 });
      assertSuccess(createdProduct.response, 201);

      const priced = await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          product_id: createdProduct.response.body.data.id,
          quantity: 2,
        },
      });
      assertSuccess(priced, 201);
      assert.equal(priced.body.data.unit_price, 50);
      assert.equal(priced.body.data.total_amount, 100);
      assert.equal(priced.body.data.quantity, 2);
      assert.equal(priced.body.data.created_by, admin.id);
      assert.equal(priced.body.data.notes, null);
      assert.equal(typeof priced.body.data.unit_price, 'number');
      assert.equal(typeof priced.body.data.total_amount, 'number');

      const overridden = await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          product_id: createdProduct.response.body.data.id,
          quantity: 3,
          unit_price: 19.99,
          notes: "note'; DROP TABLE users; --",
        },
      });
      assertSuccess(overridden, 201);
      assert.equal(overridden.body.data.unit_price, 19.99);
      assert.equal(overridden.body.data.total_amount, 59.97);
      assert.equal(overridden.body.data.notes, "note'; DROP TABLE users; --");

      const productAfter = await request('PUT', `/api/products/${createdProduct.response.body.data.id}`, {
        token: admin.token,
        body: { current_price: 80 },
      });
      assertSuccess(productAfter);
      assert.equal(productAfter.body.data.current_price, 80);

      const original = await request('GET', `/api/transactions/${priced.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(original.body.data.unit_price, 50);
      assert.equal(original.body.data.total_amount, 100);

      const usersRemain = await countRows('users', 'id = $1', [admin.id]);
      assert.equal(usersRemain, 1);
    });

    it('updates quantity and price and recalculates the total', async () => {
      const created = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerB.id, product_id: product.id, quantity: 1, unit_price: 10 },
      });
      assertSuccess(created, 201);

      const updated = await request('PUT', `/api/transactions/${created.body.data.id}`, {
        token: admin.token,
        body: { quantity: 4, unit_price: 10.25, notes: 'adjusted' },
      });
      assertSuccess(updated);
      assert.equal(updated.body.data.quantity, 4);
      assert.equal(updated.body.data.unit_price, 10.25);
      assert.equal(updated.body.data.total_amount, 41);
      assert.equal(updated.body.data.notes, 'adjusted');
      assert.equal(updated.body.data.customer_id, customerB.id);

      const emptyUpdate = await request('PUT', `/api/transactions/${created.body.data.id}`, {
        token: admin.token,
        body: {},
      });
      assertSuccess(emptyUpdate);
      assert.equal(emptyUpdate.body.data.total_amount, 41);

      const nullNotes = await request('PUT', `/api/transactions/${created.body.data.id}`, {
        token: admin.token,
        body: { notes: null },
      });
      assertError(nullNotes, 400, 'notes');
      const afterReject = await request('GET', `/api/transactions/${created.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(afterReject.body.data.notes, 'adjusted');
    });

    it('filters admin transaction lists by customer and rejects bad filters', async () => {
      const listed = await request('GET', '/api/transactions', {
        token: admin.token,
        query: { customer_id: customerA.id },
      });
      assertSuccess(listed);
      assert.ok(listed.body.data.length > 0);
      assert.ok(listed.body.data.every((item) => item.customer_id === customerA.id));

      for (const customerId of ['abc', '0', '-1', '1.5', '']) {
        const response = await request('GET', '/api/transactions', {
          token: admin.token,
          query: { customer_id: customerId },
        });
        assertError(response, 400, 'customer_id');
      }
    });

    it('rejects invalid transactions and missing related records', async () => {
      const cases = [
        [{ customer_id: customerA.id, product_id: product.id, quantity: 0 }, 'quantity'],
        [{ customer_id: customerA.id, product_id: product.id, quantity: -1 }, 'quantity'],
        [{ customer_id: customerA.id, product_id: product.id, quantity: 1.5 }, 'quantity'],
        [{ customer_id: customerA.id, product_id: product.id, quantity: 1, unit_price: 0 }, 'unit_price'],
        [{ customer_id: customerA.id, product_id: product.id, quantity: 1, unit_price: -2 }, 'unit_price'],
        [{ customer_id: '1', product_id: product.id, quantity: 1 }, 'customer_id'],
        [{ product_id: product.id, quantity: 1 }, 'customer_id'],
      ];

      for (const [body, field] of cases) {
        const response = await request('POST', '/api/transactions', { token: admin.token, body });
        assertError(response, 400, field);
      }

      const missingCustomer = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: MISSING_ID, product_id: product.id, quantity: 1 },
      });
      const missingProduct = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerA.id, product_id: MISSING_ID, quantity: 1 },
      });
      assertError(missingCustomer, 404, 'Customer not found');
      assertError(missingProduct, 404, 'Product not found');

      const created = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerA.id, product_id: product.id, quantity: 1 },
      });
      const missingProductUpdate = await request('PUT', `/api/transactions/${created.body.data.id}`, {
        token: admin.token,
        body: { product_id: MISSING_ID },
      });
      assertError(missingProductUpdate, 404, 'Product not found');
    });

    it('returns 400 for an invalid transaction id and 404 for a missing transaction', async () => {
      for (const path of ['/api/transactions/abc', '/api/transactions/0', '/api/transactions/-8']) {
        const response = await request('GET', path, { token: admin.token });
        assertError(response, 400, 'id');
      }

      const fetched = await request('GET', `/api/transactions/${MISSING_ID}`, { token: admin.token });
      const updated = await request('PUT', `/api/transactions/${MISSING_ID}`, {
        token: admin.token,
        body: { quantity: 2 },
      });
      const removed = await request('DELETE', `/api/transactions/${MISSING_ID}`, { token: admin.token });
      assertError(fetched, 404, 'Transaction not found');
      assertError(updated, 404, 'Transaction not found');
      assertError(removed, 404, 'Transaction not found');
    });
  });

  suite('payments and transaction relationships', () => {
    it('accepts a balance payment and a payment linked to that customer transaction', async () => {
      const sale = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerA.id, product_id: product.id, quantity: 1, unit_price: 30 },
      });
      assertSuccess(sale, 201);

      const linked = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          transaction_id: sale.body.data.id,
          amount: 12.5,
          payment_method: 'cash',
          notes: 'partial',
        },
      });
      assertSuccess(linked, 201);
      assert.equal(linked.body.data.customer_id, customerA.id);
      assert.equal(linked.body.data.transaction_id, sale.body.data.id);
      assert.equal(linked.body.data.amount, 12.5);
      assert.equal(linked.body.data.payment_method, 'cash');
      assert.equal(linked.body.data.created_by, admin.id);
      assert.equal(typeof linked.body.data.amount, 'number');

      const general = await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: customerA.id, amount: 4, payment_method: 'transfer' },
      });
      assertSuccess(general, 201);
      assert.equal(general.body.data.transaction_id, null);

      const explicitNull = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          transaction_id: null,
          amount: 1,
          payment_method: 'cash',
        },
      });
      assertSuccess(explicitNull, 201);
      assert.equal(explicitNull.body.data.transaction_id, null);

      const fetched = await request('GET', `/api/payments/${linked.body.data.id}`, { token: admin.token });
      assertSuccess(fetched);
      assert.equal(fetched.body.data.id, linked.body.data.id);

      const cleared = await request('PUT', `/api/payments/${linked.body.data.id}`, {
        token: admin.token,
        body: { transaction_id: null, notes: 'now general' },
      });
      assertSuccess(cleared);
      assert.equal(cleared.body.data.transaction_id, null);
      assert.equal(cleared.body.data.amount, 12.5);
      assert.equal(cleared.body.data.notes, 'now general');

      const relinked = await request('PUT', `/api/payments/${linked.body.data.id}`, {
        token: admin.token,
        body: { transaction_id: sale.body.data.id, amount: 15 },
      });
      assertSuccess(relinked);
      assert.equal(relinked.body.data.transaction_id, sale.body.data.id);
      assert.equal(relinked.body.data.amount, 15);
    });

    it('rejects a payment whose transaction belongs to another customer and does not insert it', async () => {
      const sale = await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerB.id, product_id: product.id, quantity: 1, unit_price: 8 },
      });
      const before = await countRows('payments', 'customer_id = $1', [customerA.id]);

      const response = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          transaction_id: sale.body.data.id,
          amount: 8,
          payment_method: 'cash',
        },
      });
      assertError(response, 400, 'transaction_id does not belong to this customer');
      assert.equal(await countRows('payments', 'customer_id = $1', [customerA.id]), before);

      const missingTransaction = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerA.id,
          transaction_id: MISSING_ID,
          amount: 8,
          payment_method: 'cash',
        },
      });
      assertError(missingTransaction, 400, 'transaction_id does not belong to this customer');

      const missingCustomer = await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: MISSING_ID, amount: 8, payment_method: 'cash' },
      });
      assertError(missingCustomer, 404, 'Customer not found');

      const ownPayment = await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: customerA.id, amount: 2, payment_method: 'cash' },
      });
      const relink = await request('PUT', `/api/payments/${ownPayment.body.data.id}`, {
        token: admin.token,
        body: { transaction_id: sale.body.data.id },
      });
      assertError(relink, 400, 'transaction_id does not belong to this customer');

      const stillUnlinked = await request('GET', `/api/payments/${ownPayment.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(stillUnlinked.body.data.transaction_id, null);
    });

    it('rejects invalid payments and bad list filters', async () => {
      const cases = [
        [{ customer_id: customerA.id, amount: 0, payment_method: 'cash' }, 'amount'],
        [{ customer_id: customerA.id, amount: -5, payment_method: 'cash' }, 'amount'],
        [{ customer_id: customerA.id, amount: '5', payment_method: 'cash' }, 'amount'],
        [{ customer_id: customerA.id, amount: 5, payment_method: '' }, 'payment_method'],
        [{ amount: 5, payment_method: 'cash' }, 'customer_id'],
      ];

      for (const [body, field] of cases) {
        const response = await request('POST', '/api/payments', { token: admin.token, body });
        assertError(response, 400, field);
      }

      for (const customerId of ['nope', '0', '-4']) {
        const response = await request('GET', '/api/payments', {
          token: admin.token,
          query: { customer_id: customerId },
        });
        assertError(response, 400, 'customer_id');
      }
    });

    it('filters payments by customer for an admin', async () => {
      const listed = await request('GET', '/api/payments', {
        token: admin.token,
        query: { customer_id: customerB.id },
      });
      assertSuccess(listed);
      assert.ok(listed.body.data.length > 0);
      assert.ok(listed.body.data.every((item) => item.customer_id === customerB.id));
    });

    it('returns 400 for an invalid payment id and 404 for a missing payment', async () => {
      for (const path of ['/api/payments/abc', '/api/payments/0', '/api/payments/-3']) {
        const response = await request('GET', path, { token: admin.token });
        assertError(response, 400, 'id');
      }

      const fetched = await request('GET', `/api/payments/${MISSING_ID}`, { token: admin.token });
      const updated = await request('PUT', `/api/payments/${MISSING_ID}`, {
        token: admin.token,
        body: { amount: 3 },
      });
      const removed = await request('DELETE', `/api/payments/${MISSING_ID}`, { token: admin.token });
      assertError(fetched, 404, 'Payment not found');
      assertError(updated, 404, 'Payment not found');
      assertError(removed, 404, 'Payment not found');
    });

    it('blocks deleting a transaction or customer while a payment still references them', async () => {
      const createdCustomer = await createCustomer('linked-delete');
      const createdProduct = await createProduct('linked-delete', { current_price: 25 });
      assertSuccess(createdCustomer.response, 201);
      assertSuccess(createdProduct.response, 201);

      const sale = await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: createdCustomer.response.body.data.id,
          product_id: createdProduct.response.body.data.id,
          quantity: 2,
        },
      });
      const payment = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: createdCustomer.response.body.data.id,
          transaction_id: sale.body.data.id,
          amount: 10,
          payment_method: 'cash',
        },
      });
      assertSuccess(sale, 201);
      assertSuccess(payment, 201);
      assert.equal(sale.body.data.total_amount, 50);

      const deleteCustomer = await request('DELETE', `/api/customers/${createdCustomer.response.body.data.id}`, {
        token: admin.token,
      });
      const deleteProduct = await request('DELETE', `/api/products/${createdProduct.response.body.data.id}`, {
        token: admin.token,
      });
      const deleteTransaction = await request('DELETE', `/api/transactions/${sale.body.data.id}`, {
        token: admin.token,
      });
      assertError(deleteCustomer, 409, 'cannot be deleted');
      assertError(deleteProduct, 409, 'cannot be deleted');
      assertError(deleteTransaction, 409, 'cannot be deleted');

      const deactivate = await request('PUT', `/api/products/${createdProduct.response.body.data.id}`, {
        token: admin.token,
        body: { active: false },
      });
      assertSuccess(deactivate);
      assert.equal(deactivate.body.data.active, false);

      const customerStillThere = await request(
        'GET',
        `/api/customers/${createdCustomer.response.body.data.id}`,
        { token: admin.token }
      );
      assertSuccess(customerStillThere);
      const stillLogsIn = await login(createdCustomer.body.email);
      assertSuccess(stillLogsIn);

      const removedPayment = await request('DELETE', `/api/payments/${payment.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removedPayment);

      const removedTransaction = await request('DELETE', `/api/transactions/${sale.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removedTransaction);

      const removedProduct = await request('DELETE', `/api/products/${createdProduct.response.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removedProduct);

      const removedCustomer = await request(
        'DELETE',
        `/api/customers/${createdCustomer.response.body.data.id}`,
        { token: admin.token }
      );
      assertSuccess(removedCustomer);
      assert.equal(await countRows('users', 'id = $1', [createdCustomer.response.body.data.user_id]), 0);
    });
  });

  suite('customer balance and summary', () => {
    async function balanceOf(customerId, token = admin.token) {
      const path =
        token === admin.token ? `/api/customers/${customerId}/balance` : '/api/customers/me/balance';
      const response = await request('GET', path, { token });
      assertSuccess(response);
      return response.body.data;
    }

    it('starts at zero and subtracts linked and unlinked payments from charges', async () => {
      const createdCustomer = await createCustomer('balance');
      const createdProduct = await createProduct('balance', { current_price: 40 });
      assertSuccess(createdCustomer.response, 201);
      assertSuccess(createdProduct.response, 201);
      const customerId = createdCustomer.response.body.data.id;
      const loggedIn = await login(createdCustomer.body.email);
      assertSuccess(loggedIn);
      const customerToken = loggedIn.body.data.token;

      const empty = await balanceOf(customerId);
      assert.deepEqual(empty, {
        customer_id: customerId,
        total_charges: 0,
        total_payments: 0,
        outstanding_balance: 0,
      });

      const selfEmpty = await balanceOf(customerId, customerToken);
      assert.deepEqual(selfEmpty, empty);

      const firstSale = await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: customerId,
          product_id: createdProduct.response.body.data.id,
          quantity: 2,
        },
      });
      const secondSale = await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: customerId,
          product_id: createdProduct.response.body.data.id,
          quantity: 1,
          unit_price: 19.99,
        },
      });
      assert.equal(firstSale.body.data.total_amount, 80);
      assert.equal(secondSale.body.data.total_amount, 19.99);

      let balance = await balanceOf(customerId);
      assert.equal(balance.total_charges, 99.99);
      assert.equal(balance.total_payments, 0);
      assert.equal(balance.outstanding_balance, 99.99);

      const linked = await request('POST', '/api/payments', {
        token: admin.token,
        body: {
          customer_id: customerId,
          transaction_id: secondSale.body.data.id,
          amount: 19.99,
          payment_method: 'cash',
        },
      });
      const general = await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: customerId, amount: 20, payment_method: 'transfer' },
      });
      assertSuccess(linked, 201);
      assertSuccess(general, 201);

      balance = await balanceOf(customerId, customerToken);
      assert.equal(balance.total_charges, 99.99);
      assert.equal(balance.total_payments, 39.99);
      assert.equal(balance.outstanding_balance, 60);

      const otherBalance = await balanceOf(customerB.id);
      assert.equal(typeof otherBalance.outstanding_balance, 'number');
      assert.notEqual(otherBalance.customer_id, customerId);

      const resized = await request('PUT', `/api/transactions/${firstSale.body.data.id}`, {
        token: admin.token,
        body: { quantity: 3 },
      });
      assert.equal(resized.body.data.total_amount, 120);

      balance = await balanceOf(customerId);
      assert.equal(balance.total_charges, 139.99);
      assert.equal(balance.total_payments, 39.99);
      assert.equal(balance.outstanding_balance, 100);

      const increasedPayment = await request('PUT', `/api/payments/${general.body.data.id}`, {
        token: admin.token,
        body: { amount: 30 },
      });
      assert.equal(increasedPayment.body.data.amount, 30);

      balance = await balanceOf(customerId);
      assert.equal(balance.total_payments, 49.99);
      assert.equal(balance.outstanding_balance, 90);

      const removed = await request('DELETE', `/api/payments/${linked.body.data.id}`, {
        token: admin.token,
      });
      assertSuccess(removed);

      balance = await balanceOf(customerId);
      assert.equal(balance.total_charges, 139.99);
      assert.equal(balance.total_payments, 30);
      assert.equal(balance.outstanding_balance, 109.99);

      const summary = await request('GET', `/api/customers/${customerId}/summary`, { token: admin.token });
      const selfSummary = await request('GET', '/api/customers/me/summary', { token: customerToken });
      assertSuccess(summary);
      assertSuccess(selfSummary);
      assert.equal(summary.body.data.customer.id, customerId);
      assert.deepEqual(summary.body.data.balance, balance);
      assert.deepEqual(selfSummary.body.data.balance, balance);
      assert.equal(summary.body.data.recent_transactions.length, 2);
      assert.equal(summary.body.data.recent_payments.length, 1);
      assert.equal(summary.body.data.recent_payments[0].amount, 30);
      assert.ok(summary.body.data.recent_transactions.every((item) => typeof item.total_amount === 'number'));
      assert.ok(summary.body.data.recent_transactions.every((item) => typeof item.unit_price === 'number'));
      assert.equal(summary.body.data.recent_transactions[0].product_name, createdProduct.body.name);
      assertNoSecrets(summary.body);

      const priceNow = await request('GET', `/api/products/${createdProduct.response.body.data.id}`, {
        token: admin.token,
      });
      assert.equal(priceNow.body.data.current_price, 40);
      assert.ok(summary.body.data.recent_transactions.some((item) => item.unit_price === 19.99));
    });

    it('allows a payment larger than the current charges', async () => {
      const createdCustomer = await createCustomer('overpay');
      const createdProduct = await createProduct('overpay', { current_price: 50 });
      const customerId = createdCustomer.response.body.data.id;

      await request('POST', '/api/transactions', {
        token: admin.token,
        body: { customer_id: customerId, product_id: createdProduct.response.body.data.id, quantity: 1 },
      });
      await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: customerId, amount: 80, payment_method: 'cash' },
      });

      const balance = await request('GET', `/api/customers/${customerId}/balance`, { token: admin.token });
      assertSuccess(balance);
      assert.equal(balance.body.data.total_charges, 50);
      assert.equal(balance.body.data.total_payments, 80);
      assert.equal(balance.body.data.outstanding_balance, -30);
    });

    it('returns the ten most recent transactions and payments', async () => {
      const createdCustomer = await createCustomer('summary-limit');
      const createdProduct = await createProduct('summary-limit', { current_price: 5 });
      const customerId = createdCustomer.response.body.data.id;
      const transactionIds = [];

      for (let index = 0; index < 11; index += 1) {
        const sale = await request('POST', '/api/transactions', {
          token: admin.token,
          body: {
            customer_id: customerId,
            product_id: createdProduct.response.body.data.id,
            quantity: 1,
            notes: `sale-${index}`,
          },
        });
        assertSuccess(sale, 201);
        transactionIds.push(sale.body.data.id);
      }

      for (let index = 0; index < 11; index += 1) {
        const payment = await request('POST', '/api/payments', {
          token: admin.token,
          body: {
            customer_id: customerId,
            amount: 1,
            payment_method: 'cash',
            notes: `pay-${index}`,
          },
        });
        assertSuccess(payment, 201);
      }

      const summary = await request('GET', `/api/customers/${customerId}/summary`, { token: admin.token });
      assertSuccess(summary);
      assert.equal(summary.body.data.recent_transactions.length, 10);
      assert.equal(summary.body.data.recent_payments.length, 10);
      assert.equal(
        summary.body.data.recent_transactions.some((item) => item.id === transactionIds[0]),
        false
      );
      assert.ok(summary.body.data.recent_transactions.some((item) => item.id === transactionIds[10]));
      assert.equal(summary.body.data.balance.total_charges, 55);
      assert.equal(summary.body.data.balance.total_payments, 11);
      assert.equal(summary.body.data.balance.outstanding_balance, 44);
    });

    it('keeps one customer balance independent of another customer', async () => {
      const first = await createCustomer('isolated-a');
      const second = await createCustomer('isolated-b');
      const createdProduct = await createProduct('isolated', { current_price: 15 });

      await request('POST', '/api/transactions', {
        token: admin.token,
        body: {
          customer_id: first.response.body.data.id,
          product_id: createdProduct.response.body.data.id,
          quantity: 2,
        },
      });
      await request('POST', '/api/payments', {
        token: admin.token,
        body: { customer_id: second.response.body.data.id, amount: 6, payment_method: 'cash' },
      });

      const firstBalance = await request('GET', `/api/customers/${first.response.body.data.id}/balance`, {
        token: admin.token,
      });
      const secondBalance = await request('GET', `/api/customers/${second.response.body.data.id}/balance`, {
        token: admin.token,
      });
      assert.equal(firstBalance.body.data.outstanding_balance, 30);
      assert.equal(firstBalance.body.data.total_payments, 0);
      assert.equal(secondBalance.body.data.total_charges, 0);
      assert.equal(secondBalance.body.data.outstanding_balance, -6);
    });

    it('returns 404 for balance and summary of a missing customer', async () => {
      const balance = await request('GET', `/api/customers/${MISSING_ID}/balance`, { token: admin.token });
      const summary = await request('GET', `/api/customers/${MISSING_ID}/summary`, { token: admin.token });
      assertError(balance, 404, 'Customer not found');
      assertError(summary, 404, 'Customer not found');
    });
  });

  suite('inputs that violate database limits', () => {
    it('rejects an id that does not fit in a 32-bit integer', async () => {
      const paths = [
        `/api/customers/${OUT_OF_RANGE_ID}`,
        `/api/customers/${OUT_OF_RANGE_ID}/balance`,
        `/api/customers/${OUT_OF_RANGE_ID}/summary`,
        `/api/products/${OUT_OF_RANGE_ID}`,
        `/api/transactions/${OUT_OF_RANGE_ID}`,
        `/api/payments/${OUT_OF_RANGE_ID}`,
      ];
      const failures = [];

      for (const path of paths) {
        const response = await request('GET', path, { token: admin.token });

        if (response.status !== 400 && response.status !== 404) {
          failures.push(`${path} -> ${response.status} ${JSON.stringify(response.body)}`);
        }
      }

      assert.deepEqual(failures, []);
    });

    it('rejects customer fields that are longer than the database columns', async () => {
      const attempts = [
        ['name', await createCustomer('long-name', { name: 'N'.repeat(256) })],
        ['phone', await createCustomer('long-phone', { phone: '1'.repeat(21) })],
        ['address', await createCustomer('long-address', { address: 'A'.repeat(501) })],
        [
          'email',
          await createCustomer('long-email', {
            email: `${'a'.repeat(250)}@integration.hydra-care.test`,
          }),
        ],
      ];
      const failures = [];

      for (const [field, result] of attempts) {
        if (result.response.status !== 400 || !result.response.body.message?.toLowerCase().includes(field)) {
          failures.push(
            `${field} -> ${result.response.status} ${JSON.stringify(result.response.body)}`
          );
        }
      }

      assert.deepEqual(failures, []);
    });

    it('rejects product, payment, and transaction values outside database limits', async () => {
      const createdCustomer = await createCustomer('payment-limits');
      assertSuccess(createdCustomer.response, 201);
      const customerId = createdCustomer.response.body.data.id;
      const failures = [];

      const attempts = [
        ['product name', await createProduct('long-name', { name: `itest-${'p'.repeat(260)}` })],
        ['current_price overflow', await createProduct('huge-price', { current_price: 100_000_000 })],
        ['current_price precision', await createProduct('extra-cents', { current_price: 1.005 })],
        [
          'quantity',
          {
            response: await request('POST', '/api/transactions', {
              token: admin.token,
              body: { customer_id: customerA.id, product_id: product.id, quantity: 2_147_483_648 },
            }),
          },
        ],
        [
          'unit_price 1.005',
          {
            response: await request('POST', '/api/transactions', {
              token: admin.token,
              body: { customer_id: customerA.id, product_id: product.id, quantity: 1, unit_price: 1.005 },
            }),
          },
        ],
        [
          'unit_price 0.001',
          {
            response: await request('POST', '/api/transactions', {
              token: admin.token,
              body: { customer_id: customerA.id, product_id: product.id, quantity: 1, unit_price: 0.001 },
            }),
          },
        ],
        [
          'payment_method',
          {
            response: await request('POST', '/api/payments', {
              token: admin.token,
              body: { customer_id: customerId, amount: 1, payment_method: 'm'.repeat(51) },
            }),
          },
        ],
        [
          'amount',
          {
            response: await request('POST', '/api/payments', {
              token: admin.token,
              body: { customer_id: customerId, amount: 100_000_000, payment_method: 'cash' },
            }),
          },
        ],
      ];

      for (const [label, result] of attempts) {
        if (result.response.status !== 400) {
          failures.push(`${label} -> ${result.response.status} ${JSON.stringify(result.response.body)}`);
        }
      }

      assert.deepEqual(failures, []);
    });
  });
});
