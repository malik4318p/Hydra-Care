import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  legacyAuthCreateAttributes,
  linkLegacyCustomer76,
  redact,
} from '../scripts/linkLegacyCustomer76.js';

const authUserId = '33333333-3333-4333-8333-333333333333';
const passwordHash = '$2b$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ012';

function user(overrides = {}) {
  return {
    id: 76,
    email: 't@gmail.com',
    role: 'customer',
    auth_user_id: null,
    password_hash: passwordHash,
    ...overrides,
  };
}

function harness(overrides = {}) {
  const calls = [];
  const db = {
    async getLegacyUser(id) {
      calls.push(['getLegacyUser', id]);
      return user();
    },
    async linkAuthUser(input) {
      calls.push(['linkAuthUser', input]);
      return true;
    },
    ...overrides.db,
  };
  const authAdmin = {
    async findByEmail(email) {
      calls.push(['findByEmail', email]);
      return [];
    },
    async createWithPasswordHash(attributes) {
      calls.push(['createWithPasswordHash', attributes]);
      return { id: authUserId };
    },
    async deleteUser(id) {
      calls.push(['deleteUser', id]);
    },
    ...overrides.authAdmin,
  };
  return { calls, db, authAdmin };
}

describe('link legacy customer 76', () => {
  it('imports the existing bcrypt hash and links only that user', async () => {
    const { calls, db, authAdmin } = harness();
    const result = await linkLegacyCustomer76({ db, authAdmin });

    assert.equal(result.ok, true);
    assert.equal(result.userId, 76);
    assert.equal(result.email, 't@gmail.com');
    assert.equal(result.authUserId, authUserId);
    assert.equal(JSON.stringify(result).includes(passwordHash), false);
    assert.deepEqual(calls[0], ['getLegacyUser', 76]);
    assert.deepEqual(
      calls.find((call) => call[0] === 'createWithPasswordHash')[1],
      legacyAuthCreateAttributes('t@gmail.com', passwordHash)
    );
    assert.equal(
      Object.hasOwn(calls.find((call) => call[0] === 'createWithPasswordHash')[1], 'password'),
      false
    );
    assert.deepEqual(calls.find((call) => call[0] === 'linkAuthUser')[1], {
      id: 76,
      email: 't@gmail.com',
      authUserId,
    });
    assert.equal(calls.some((call) => call[0] === 'deleteUser'), false);
  });

  it('does not create an Auth user when one already exists for the email', async () => {
    const { calls, db, authAdmin } = harness({
      authAdmin: {
        async findByEmail() {
          calls.push(['findByEmail', 't@gmail.com']);
          return ['44444444-4444-4444-8444-444444444444'];
        },
      },
    });
    const result = await linkLegacyCustomer76({ db, authAdmin });

    assert.equal(result.ok, false);
    assert.match(result.message, /already exists/);
    assert.equal(calls.some((call) => call[0] === 'createWithPasswordHash'), false);
    assert.equal(calls.some((call) => call[0] === 'linkAuthUser'), false);
  });

  it('deletes the new Auth user when the link update fails', async () => {
    const { calls, db, authAdmin } = harness({
      db: {
        async linkAuthUser() {
          calls.push(['linkAuthUser']);
          return false;
        },
      },
    });
    const result = await linkLegacyCustomer76({ db, authAdmin });

    assert.equal(result.ok, false);
    assert.match(result.message, /deleted/);
    assert.equal(result.message.includes(passwordHash), false);
    assert.deepEqual(
      calls.filter((call) => call[0] === 'deleteUser'),
      [['deleteUser', authUserId]]
    );
  });

  it('stops before Auth creation when the row is not an unlinked customer', async () => {
    for (const row of [
      null,
      user({ role: 'admin' }),
      user({ auth_user_id: authUserId }),
      user({ password_hash: null }),
    ]) {
      const { calls, db, authAdmin } = harness({
        db: {
          async getLegacyUser() {
            calls.push(['getLegacyUser', 76]);
            return row;
          },
        },
      });
      const result = await linkLegacyCustomer76({ db, authAdmin });
      assert.equal(result.ok, false);
      assert.equal(calls.some((call) => call[0] === 'createWithPasswordHash'), false);
    }
  });

  it('uses the installed Admin API password_hash field and does not change Express login', () => {
    const attributes = legacyAuthCreateAttributes('t@gmail.com', passwordHash);
    assert.deepEqual(Object.keys(attributes).sort(), ['email', 'email_confirm', 'password_hash']);
    assert.equal(attributes.email_confirm, true);
    assert.equal(redact(`failed ${passwordHash}`).includes(passwordHash), false);

    const root = fileURLToPath(new URL('..', import.meta.url));
    const authService = readFileSync(`${root}/src/services/authService.js`, 'utf8');
    const script = readFileSync(`${root}/scripts/linkLegacyCustomer76.js`, 'utf8');
    assert.match(authService, /bcrypt\.compare\(password, user\.password_hash\)/);
    assert.match(script, /SET auth_user_id = \$1/);
    assert.doesNotMatch(script, /SET password_hash|password:/);
    assert.doesNotMatch(script, /UPDATE auth\.users|INSERT INTO auth\.users|DELETE FROM auth\.users/);
  });
});
