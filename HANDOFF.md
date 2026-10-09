# HydraCare handoff

Read this file before changing anything. It is the project history through 30 September 2026. Do not invent earlier decisions, applied SQL, or device state. If this file and the code disagree, trust the code and say so.

Repo: `/Users/apple/Desktop/hydra-care`

There are two apps:

- `backend/` — Express + PostgreSQL (Supabase Postgres). Still the source of customer create, name/phone/email update, bcrypt login, and the Express JWT.
- `mobile/` — Flutter. Pubspec name is still `purify_mobile`. Visible name is HydraCare. Package `com.hydracare.hydracare_mobile`. Activity `.MainActivity`.

Do not print secrets, password hashes, JWTs, or Supabase access tokens. `backend/.env` holds `DATABASE_URL`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`. `PORT` is not in `.env` and defaults to 5000. Never put `SUPABASE_SECRET_KEY` or a service-role key in Flutter.

---

## What the product is

Record-keeping for a bottled-water business. Roles are `admin` and `customer` only.

- Admin creates and edits customers, products, sales (transactions), and payments.
- Customer sees their own summary: profile, full balance, latest 10 sales, latest 10 payments.
- Outstanding balance is not stored. It is `SUM(transactions.total_amount) - SUM(payments.amount)`.
- There is no delete in the Flutter admin UI. Express has customer delete, but Flutter services never called DELETE, so delete was not added.

Login is email and password only. There is no phone/password login.

---

## Machine and device (do not re-derive)

- Mac: macOS 12.7.6, Intel.
- Flutter 3.35.7, Dart 3.9.2. SDK `/Users/apple/development/flutter`. Do not upgrade Flutter.
- Android SDK `/Users/apple/Library/Android/sdk`.
- JDK: Android Studio JBR 21 at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`.
- Phone: Samsung SM A716U, ADB serial `R5CN70GPP6Z`, Android 13 API 33, arm64. USB. Wireless adb on 5555 was refused.
- LAN IP used for the phone: `192.168.100.97`. Express listens on all interfaces, port 5000, CORS open.
- Health: `GET /api/health` returns `{"success":true,"message":"API is running"}`. `GET /api` alone is 404.
- Gradle wrapper: 8.11.1 from services.gradle.org, already extracted under `~/.gradle/wrapper/dists/gradle-8.11.1-bin/`. Do not switch back to Gradle 8.12 from GitHub (HTTP 500). AGP 8.9.1 needs Gradle >= 8.11.1. Kotlin 2.1.0.
- NDK 27.0.12077973 is installed. Do not re-download it.
- `mobile/android/gradle.properties` heap is `-Xmx2G` and MaxMetaspace 512m (the machine has 16 GB; the old 8G/4G setting was reduced).
- Builds must export `HOME=/Users/apple` and `GRADLE_USER_HOME=/Users/apple/.gradle` or the sandbox redirects Gradle and re-downloads. Use `JAVA_HOME` = the Android Studio JBR path above and `ANDROID_HOME=/Users/apple/Library/Android/sdk`.
- Debug and profile Android manifests have `INTERNET` and `android:usesCleartextTraffic=true` so the phone can call `http://192.168.100.97:5000/api`.
- Debug APK path: `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- Install: `adb install -r` then `am start -n com.hydracare.hydracare_mobile/.MainActivity`.
- Samsung caches launcher name and icon. If they look stale, remove the home-screen shortcut and add it again.

The last APK installed on the phone is the pre-Supabase HydraCare rename build (admin CRUD, balances, no debug banner, water-drop icon, name HydraCare). Phase 5 and Phase 6 Flutter changes were analyzed only. The app was not rebuilt or reinstalled after Supabase login or the data migration. Do not assume the phone is running the current source.

---

## Architecture now

Flutter screens do not call HTTP themselves. `main.dart` builds the services.

Startup:

```dart
await Supabase.initialize(
  url: SupabaseConfig.projectUrl,          // --dart-define=SUPABASE_URL
  publishableKey: SupabaseConfig.publishableKey, // --dart-define=SUPABASE_PUBLISHABLE_KEY
);
```

`supabase_flutter` 2.17.2 uses `publishableKey`. `anonKey` is deprecated. Do not hardcode the key.

`ApiClient` still attaches `Authorization: Bearer <Express JWT>` from `TokenStorage`. It does not send the Supabase access token. A 401 on an authenticated Express call clears the session via `authService.handleUnauthorized`.

Login (`AuthService.login`):

1. `Supabase.instance.client.auth.signInWithPassword(email, password)`.
2. If that throws `AuthException`, map it to `ApiException` and do not call the bridge.
3. If the session is empty, sign out Supabase and throw.
4. Direct `http.post` (not `ApiClient`) to `${ApiConfig.baseUrl}/auth/supabase-login` with `Authorization: Bearer <supabase access token>`, 20 second timeout.
5. Store only the returned Express JWT and `User` in `TokenStorage` (`auth_token`, `auth_user` via `flutter_secure_storage`).
6. If the bridge or the save fails, sign out Supabase and clear storage. Do not leave a partial session.

Logout signs out Supabase (local scope; AuthException swallowed) and clears Express storage.

`restore()`: if an Express JWT and user JSON already exist, restore them and do not call Supabase login or the bridge. If the Express JWT is missing, sign out Supabase and clear storage. Do not mint a replacement JWT. Expired Express JWTs are restored until the next `ApiClient` 401.

`User.isAdmin` is `role == 'admin'`. `app.dart` sends admins to `AdminHomeScreen` and every other signed-in role to `CustomerHomeScreen`.

Express bridge `POST /api/auth/supabase-login`:

- Header must be `Bearer <token>`. Body is ignored. Identity comes only from the verified token.
- `supabase.auth.getUser(accessToken)` with the server secret. Invalid, thrown, or non-UUID → 401 `Invalid or expired token`.
- `SELECT id, name, email, role FROM public.users WHERE auth_user_id = $1`.
- No row → 401 `No application user is linked to this account`.
- Role not `admin` or `customer` → 403 `You do not have permission to perform this action`.
- Then the same `issueSession` as password login: JWT payload `{ userId, role }` where `userId` is integer `public.users.id`, expiry `7d`, response shape `{ success, data: { token, user } }`.
- Existing `POST /api/auth/login` and bcrypt are unchanged.
- Client is created with `persistSession: false` and `autoRefreshToken: false`.
- `env.js` rejects a secret that starts with `sb_publishable_`.

Run command from `mobile/`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.100.97:5000/api \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Default `API_BASE_URL` if the define is omitted: `http://192.168.100.97:5000/api`.

---

## What Flutter calls now

| Operation | Path |
| --- | --- |
| Login | Supabase `signInWithPassword`, then Express `POST /api/auth/supabase-login` |
| Logout / restore | Supabase sign-out + `TokenStorage` |
| List / create / update products | Supabase table `products` under RLS |
| List customers | Supabase `customers` embed `users!fk_customers_user` |
| Customer balance | RPC `get_customer_balance` |
| Customer "me" summary | Resolve integer customer id from `auth.uid()`, then RPC `get_customer_summary` |
| Customer address update | Supabase `customers.update({ address })` |
| Create customer (includes password) | Express `POST /api/customers` |
| Update customer name, phone, email | Express `PUT /api/customers/:id` with only `{ name, phone, email }` |
| List / create / update transactions | Supabase select with `products!fk_transactions_product`, writes via RPC |
| List / create / update payments | Supabase select, writes via RPC |

Express product, transaction, and payment routes still exist. Flutter no longer calls them. Do not delete them unless asked.

`CustomerService` only wraps `CustomerDataService.getMySummary()`. It no longer takes `ApiClient`.

`AdminService` still takes `ApiClient` for create customer and the name/phone/email PUT.

PostgREST `numeric` comes back as a string. Flutter services coerce to `num` / `int` before model `fromJson`.

There is no Flutter `getCustomer(id)`. Express still has `GET /customers/:id`. Do not add a Flutter get-by-id unless a screen already needs it.

---

## Database

Integer identity primary keys, not bigint. Money is `NUMERIC(10,2)`. FKs are `ON DELETE RESTRICT`.

Tables from `001_initial_schema.sql` (do not edit 001):

- `users`: `id`, `name`, `phone`, `email` NOT NULL UNIQUE (case-sensitive), `password_hash` VARCHAR(255) NOT NULL, `role` CHECK `admin|customer`, timestamps.
- `customers`: `id`, `user_id` UNIQUE → users, `address`, timestamps.
- `products`: `id`, `name` unique, `type` CHECK `bottle|refill`, `current_price > 0`, `active` default true.
- `transactions`: customer, product, `quantity`, `unit_price`, `total_amount`, `notes`, `created_by`. CHECK `total_amount = quantity * unit_price`. `unit_price` is independent of `products.current_price`.
- `payments`: customer, nullable `transaction_id`, `amount`, `payment_method` VARCHAR(50), `notes`, `created_by`. No `updated_at`.

`002_supabase_auth_link.sql` (user applied it):

```sql
ALTER TABLE public.users
    ADD COLUMN auth_user_id UUID NULL,
    ADD CONSTRAINT uq_users_auth_user_id UNIQUE (auth_user_id),
    ADD CONSTRAINT fk_users_auth_user
        FOREIGN KEY (auth_user_id) REFERENCES auth.users (id)
        ON DELETE SET NULL;
```

`ON DELETE SET NULL` keeps the public user if the Auth user is deleted. PostgreSQL UNIQUE allows multiple NULLs. Do not swap the integer PK for the Auth UUID. `public.users.id` remains the FK target everywhere.

`003_supabase_rls.sql` (user applied the revised version):

- `private.is_admin()` is `SECURITY DEFINER`, `search_path=public`, not in `public` so PostgREST does not expose it. It selects `public.users` where `auth_user_id = auth.uid()` and `role = admin`. This avoids RLS recursion.
- RLS enabled on users, customers, products, transactions, payments. Do not `FORCE ROW LEVEL SECURITY`. Table owner and the service role bypass RLS, so Express still works.
- `REVOKE ALL` from PUBLIC, anon, and authenticated, then grant only what follows.
- Users: SELECT columns except `password_hash`. Policies `users_select_own` and `users_select_admin`. No client UPDATE. No role or `password_hash` change from the client.
- Customers: SELECT. UPDATE `(address)` only, admin. Policies `customers_select_own`, `customers_select_admin`, `customers_update_admin`. No client INSERT or DELETE.
- Products: authenticated SELECT. Admin INSERT `(name, type, current_price)` and UPDATE `(name, type, current_price, active)`. No DELETE. `updated_at` is not in the UPDATE grant, so Flutter must not set it.
- Transactions and payments: SELECT only (own row for a customer, all for admin). No INSERT/UPDATE/DELETE grants or policies. Writes go through the RPCs in 004.
- A comment in 003 says email changes must stay aligned with `auth.users.email` through a later secure flow. That flow does not exist yet.

`004_supabase_rpc.sql` (user said it was executed and verified; the agent did not execute it):

All six functions are `SECURITY DEFINER`, `SET search_path = public`, `auth.uid()` schema-qualified. `REVOKE ALL` from PUBLIC and anon. `GRANT EXECUTE` to `authenticated` only.

Signatures (integer, not bigint):

- `public.create_transaction(customer_id integer, product_id integer, quantity integer, unit_price numeric DEFAULT NULL, notes text DEFAULT NULL) RETURNS public.transactions`
- `public.update_transaction(transaction_id integer, product_id integer, quantity integer, unit_price numeric DEFAULT NULL, notes text DEFAULT NULL) RETURNS public.transactions`
- `public.create_payment(customer_id integer, transaction_id integer DEFAULT NULL, amount numeric DEFAULT NULL, payment_method text DEFAULT NULL, notes text DEFAULT NULL) RETURNS public.payments`
- `public.update_payment(payment_id integer, transaction_id integer DEFAULT NULL, amount numeric DEFAULT NULL, payment_method text DEFAULT NULL, notes text DEFAULT NULL) RETURNS public.payments`
- `public.get_customer_balance(target_customer_id integer) RETURNS jsonb` STABLE
- `public.get_customer_summary(target_customer_id integer) RETURNS jsonb` STABLE

Behavior locked to Express:

- `create_transaction`: admin only. Customer and product must exist. Quantity is a positive integer. NULL `unit_price` uses `products.current_price`. `unit_price` must be positive. Total is calculated in Postgres as `quantity * unit_price` after assignment to `numeric(10,2)`. `created_by` always comes from `auth.uid()` → `public.users.id`. Inactive products are allowed. Returns the new row.
- `update_transaction`: admin. Must exist. Does not change `customer_id` or `created_by`. NULL `unit_price` keeps the stored `unit_price` (historical price must not follow `products.current_price`). Recalculates total. NULL notes keep stored notes; `''` replaces. Sets `updated_at = now()`.
- `create_payment`: admin. Amount > 0. Method non-empty, max 50 chars, whitespace allowed (Express does not trim). NULL `transaction_id` is a general payment. If set, the sale must exist and belong to that customer. Missing sale and wrong customer both use the Express message `transaction_id does not belong to this customer`. `created_by` from `auth.uid()`.
- `update_payment`: admin. Does not change `customer_id` or `created_by`. Amount > 0. Method required. NULL `transaction_id` clears the link, because SQL cannot tell omit from null and Flutter always sends the field. If set, the sale must belong to the same customer. Payments have no `updated_at`.
- `get_customer_balance`: returns `customer_id`, `total_charges`, `total_payments`, `outstanding_balance`. Empty sums are 0. Rounded to 2 decimals. Admin: any existing customer. Customer: own id only. Any other id, including a nonexistent one, is a permission error so existence is not leaked.
- `get_customer_summary`: authorization runs before any profile, sale, or payment read. Unauthenticated → `unauthenticated` / 28000. Admin and missing customer → `Customer not found` / P0002. Customer mismatch or no customer row → permission / 42501. Then full balance (all rows, not just 10), profile without `password_hash`, latest 10 sales by `created_at DESC` with product name, latest 10 payments by `created_at DESC`. JSON keys match Flutter `fromJson`: `customer` (id, user_id, name, phone, email, role, address, created_at, updated_at), `balance`, `recent_transactions` (id, product_id, product_name, quantity, unit_price, total_amount, notes, created_at), `recent_payments`. Empty lists are `[]`.

Money note: Express `Math.round(qty * price * 100) / 100` can diverge from numeric assignment only when the input has more than 2 decimal places. `current_price` 1.005 is stored as 1.01 by `numeric(10,2)`.

Flutter transaction create passes `unit_price: null` when the field is blank, and omits empty notes (stored NULL). Flutter transaction update always sends unit price and `notes ?? ''`. Flutter payment create omits empty notes. Flutter payment update always sends `transactionId` (possibly null) and `notes ?? ''`.

---

## Auth data state (as last known)

Do not rerun the import script. The user said migration of existing users is complete.

Before the script, a read-only check found:

- 3 `public.users`: 1 admin (id 1) already linked, email matched `auth.users`; 2 customers with `auth_user_id` NULL.
- 2 `customers` rows. 1 `auth.users` row (the admin).
- No blank, invalid, or duplicate emails. All `password_hash` values had a bcrypt prefix `$2a` / `$2b` / `$2y`.

The user then ran `backend/scripts/migrateCustomerAuthUsers.js`. They later said both customers are linked. The agent did not re-query the database after that. Verify with SQL if a later task depends on it. Do not print hashes.

The script (do not run again unless asked):

- ESM. Uses the existing `pg` pool and `@supabase/supabase-js` Auth admin API.
- Env: `SUPABASE_URL`, `SUPABASE_SECRET_KEY` (rejects `sb_publishable_`). Loading the pool also loads `env.js`, so `DATABASE_URL` and `JWT_SECRET` must be set even though the script does not use the JWT.
- Selects `role = customer AND auth_user_id IS NULL`.
- If an Auth user already exists for that email (case-insensitive lookup), link it and do not modify the Auth user.
- Otherwise `auth.admin.createUser({ email, password_hash, email_confirm: true })`.
- Link is a transaction: `UPDATE public.users SET auth_user_id=$1 WHERE id=$2 AND role='customer' AND auth_user_id IS NULL`, and `rowCount` must be 1.
- Does not change id, email, password_hash, role, customers, transactions, or payments.
- Command from `backend/`: `node scripts/migrateCustomerAuthUsers.js`.

Phase 2B admin link was SQL the agent showed and the user ran. It linked the existing admin Auth user by email, required `role = admin`, and failed unless exactly one row matched. Do not rerun it. Verification:

```sql
SELECT u.id, u.email, u.role, u.auth_user_id, a.id AS auth_id, a.email AS auth_email
FROM public.users AS u
LEFT JOIN auth.users AS a ON a.id = u.auth_user_id
WHERE u.role = 'admin';
```

---

## Known bugs and open findings (do not fix unless asked)

### Customer list is slow

`CustomersScreen._load` in `mobile/lib/features/admin/screens/customers_screen.dart`:

- `_loading` starts true.
- `initState` calls `_load`, which sets `_loading` true again.
- Awaits `listCustomers()`.
- Then `Future.wait` of `getCustomerBalance` for every customer.
- `finally` sets `_loading` false.

The spinner `Loading customers...` covers the list and every balance RPC.

Exact list query in `customer_data_service.dart`:

`customers.select('id, user_id, address, created_at, updated_at, users!fk_customers_user(name, phone, email, role)').order('id')`

Join is `fk_customers_user`. The list tile shows name, phone, email, address, and Due. It does not show `created_at`, `updated_at`, or `role`. `role` is required by `Customer.fromJson`. `user_id` is required by the model.

RLS for an admin: `customers_select_admin` and the embedded users policy `users_select_admin`, each calling `private.is_admin()`. That is a small lookup, not the multi-second cost.

Each `get_customer_balance` is `SECURITY DEFINER` and sums all sales and all payments for that customer.

Observed by the user: first load about 6–8 seconds, later loads about 4 seconds. The obvious cause is one list request plus one balance RPC per customer, all over the network, with the spinner waiting for all of them. The first open also pays for a new HTTPS connection. Data volume is not the cause (two customers). Do not optimize until asked.

Transaction and payment screens also call `listCustomers()`, but they do not fan out balance RPCs.

### Email edit desynchronizes Auth

Edit screen `_submit` calls `adminService.updateCustomer(id, name, phone, email, address)`.

`AdminService.updateCustomer`:

1. Express `PUT /customers/:id` body `{ name, phone, email }` only. Address is omitted so Express `COALESCE` keeps the old address.
2. Then `CustomerDataService.updateAddress`, which updates only `customers.address`.

Express `customerService.updateCustomer` updates `public.users` name, phone, email, `updated_at`. It does not touch `auth.users`. Unique email violation → 409 `A user with this email already exists`.

Nothing in Flutter, Express, the bridge, or the import script calls `auth.admin.updateUser` during edit.

Result: `public.users.email` changes. `auth.users.email` does not. They are not synchronized.

Supabase `signInWithPassword` uses `auth.users.email`. The bridge maps by `auth_user_id`, not email. Login with the new email fails. Login with the old email still works, and the app then shows the new `public.users.email`.

If Express name/phone/email succeeds and the later address update fails, name/phone/email are already saved.

### Four pre-existing integration test failures

`npm test` is `node --test --test-concurrency=1 tests/integration/api.test.js`. It uses the real `DATABASE_URL`. Test emails are `*@integration.hydra-care.test`. Suite timeout 180s.

Last full run after the bridge: 44 passed, 4 failed. The same 4 failed before the bridge (an earlier run was 39 passed, 4 failed). All 5 `supabase login bridge` tests passed. Do not change production behavior to make the 4 pass.

1. `rejects a second customer whose email differs only by case` — expected 409, got 201. `users.email` unique is case-sensitive. Source: `createCustomer`.
2. `rejects an id that does not fit in a 32-bit integer` — `GET` of customers, products, transactions, payments, and customer balance/summary with id `9999999999` returns 500. Postgres `22003`. `idParamSchema` only requires a positive integer. `errorHandler` maps a missing status to 500.
3. `rejects customer fields that are longer than the database columns` — name/phone/address/email create returns 500. Zod does not enforce varchar limits. Postgres `22001`.
4. `rejects product, payment, and transaction values outside database limits` — oversized product name, `current_price` 100000000, quantity 2147483648, `unit_price` 1.005 and 0.001, long `payment_method`, amount 100000000 return 500. `current_price` 1.005 returns 201 stored as 1.01. Codes include `22001`, `22003`, and the transaction total CHECKs.

Bridge tests that passed: missing/malformed header, invalid token, Express JWT rejected as a Supabase token, valid unlinked Auth user rejected even if the body spoofs admin, linked customer exchanges for an Express JWT (body spoof ignored), `jwt.verify` payload and 7d expiry, `GET /api/products` with that Express token succeeds.

---

## Timeline

### 29 September 2026 — Android delivery

Goal: run `mobile/` on the physical phone. Android APK only. Do not install Xcode.

Blocker: Gradle wrapper HTTP 500 downloading `gradle-8.12-all.zip` from GitHub. Fixed by pointing the wrapper at local Gradle 8.11.1. Deleted the failed 8.12 cache.

Also fixed: sandbox `GRADLE_USER_HOME` causing a re-download; missing/partial NDK (CXX1101, empty `source.properties`, IPv6 stall to dl.google.com — use `curl -4`); first sandbox build failing on `engine.stamp` (rerun outside the sandbox); phone absent from USB, then it returned.

Debug APK built with `--dart-define=API_BASE_URL=http://192.168.100.97:5000/api`, installed, and launched.

### Same period — admin UI, before Supabase

- Admin create for customers, products, transactions, and payments was a placeholder snackbar. Wired to existing Express APIs. Backend was not changed.
- Admin edit via PUT: tap a row, reuse the create form, loading and errors, refresh the list. No password edit. Do not change `customer_id` on transaction or payment edit. Delete was not added.
- Admin customer list and edit show outstanding balance from `GET /customers/:id/balance`.
- Transaction unit price: optional on create (blank uses product `current_price`); total = quantity × unit price; required on edit.
- `debugShowCheckedModeBanner: false`.
- Launcher icon replaced with the attached water-drop image (source JPG under the Cursor project assets, converted to mipmap PNGs).
- Visible name set to HydraCare: Android label, iOS `CFBundleDisplayName` / `CFBundleName`, `MaterialApp` title, login heading. Pubspec name left as `purify_mobile`.

That build is what is on the phone.

### Supabase migration rules (still in force)

Plan was Flutter → Express → Supabase Postgres, becoming Flutter → Supabase Auth/Data/RPC → the same Postgres, with Express kept as a fallback.

Do not upgrade Flutter, rewrite architecture, change Express behavior to make tests pass, install Xcode, or put the Supabase secret in Flutter. Do not execute SQL or the auth-import script unless a later request explicitly says so. Do not edit `001`. Do not force RLS. Do not drop `password_hash`. Do not change integer primary keys. Do not store balance. No Edge Functions were created.

### Phase 0

Inspection and a written plan only. Canvas (not a repo file): `/Users/apple/.cursor/projects/Users-apple-Desktop-hydra-care/canvases/supabase-migration-plan.canvas.tsx`.

### Phase 1

Created only `backend/database/migrations/002_supabase_auth_link.sql`. Did not create Auth users, migrate passwords, touch Flutter or Express, enable RLS, or execute SQL. The user applied 002 later.

### Phase 2B

Auth users table had only the admin the user created in the dashboard. `public.users.auth_user_id` was still NULL. The agent showed link-by-email SQL for that one admin and did not run it. The user ran it.

### Phase 3

Created `003_supabase_rls.sql`. Before execution the user required a revision: remove authenticated INSERT/UPDATE grants and policies on transactions and payments (SELECT only); remove `GRANT UPDATE` on users and `users_update_admin`; keep customers.address admin UPDATE; keep product SELECT and admin INSERT/UPDATE. The agent showed the revised SQL and did not execute it. The user applied it. Treat RLS as live.

### Phase 4

Created only `004_supabase_rpc.sql`. Did not execute it and did not modify Flutter, Express, or 001–003. A follow-up changed only `get_customer_summary` so authorization runs before any profile, sale, or payment read. The user later said 004 was executed and verified.

### Phase 5 Step 2

Initialized `supabase_flutter` only. New `mobile/lib/config/supabase_config.dart` with `String.fromEnvironment` for URL and publishable key. `main.dart` calls `Supabase.initialize` before `runApp`. No login change yet.

### Phase 5 Step 4

Inspection only. Login was email/password. JWT lived in `TokenStorage`. `ApiClient` attached it. Logout was local. Startup restore trusted stored JSON and did not call the server.

### Phase 5 Step 4B inspection

Read-only. Reported bcrypt location, the two unlinked customers, no bad emails, and that Auth Admin `createUser({ password_hash })` can import bcrypt. Did not print hashes.

### Phase 5 Step 4B script

Created `backend/scripts/migrateCustomerAuthUsers.js` only. Did not execute it. Backend dependency `@supabase/supabase-js` ^2.117.2 was added. The user later ran the script and said both customers are linked.

### Phase 5 Step 5 — stopped

The request was to switch Flutter login to Supabase while keeping Express API calls. Inspection showed `ApiClient` can only use an Express JWT signed with `JWT_SECRET`. A Supabase access token fails `jwt.verify`. The agent stopped and changed no files. Do not store the Supabase token as the Express JWT.

### Express bridge

The user then asked for a temporary bridge. Only Express was modified: `POST /api/auth/supabase-login`. Files: `backend/src/config/env.js`, `backend/src/services/authService.js`, `backend/src/controllers/authController.js`, `backend/src/routes/authRoutes.js`, `backend/.env.example`, and tests inside `backend/tests/integration/api.test.js`. Not deployed. Flutter was not changed in that step.

### Phase 5 Step 5B

Flutter login switched to Supabase plus the bridge. `AuthService` no longer takes `ApiClient`. `import supabase_flutter hide User` so the app `User` model is not ambiguous. `LoginScreen` and `app.dart` were left unchanged. `flutter analyze` was clean. The app was not run.

### Phase 6 Step 1 — products

`mobile/lib/services/product_service.dart`. List `id, name, type, current_price, active` order by id. Insert then select single. Update by id, `maybeSingle` null → 404. Validates name, type `bottle|refill`, price > 0. Errors: `23505` → 409 `A product with this name already exists`; `42501` or RLS text → 403; `PGRST116` → 404. `AdminService` delegates. Express product routes remain.

### Phase 6 Step 2 — customer reads and address

New `mobile/lib/services/customer_data_service.dart`. `CustomerService` only loads the summary. Create customer and name/phone/email stay on Express. Address is a direct admin update. `getMySummary` resolves the integer customer id with:

`customers.select('id, users!fk_customers_user!inner(auth_user_id)').eq('users.auth_user_id', authUserId)`

It does not guess ids. Error map: `28000` or unauthenticated → 401; `P0002` or `Customer not found` → 404; `42501` or RLS text → 403; else 400.

### Phase 6 Step 3 — transactions and payments

`transaction_service.dart` and `payment_service.dart`. Reads are direct selects under RLS. Writes are the existing RPCs. Flutter does not recalculate totals or balances. `created_by` and `customer_id` stay server-side. Transaction update does not send `customer_id`. List transactions embed `products!fk_transactions_product(name)` and map it to `product_name`.

Error map: `28000` → 401; `P0002` → 404 with the server message; `42501`, `admin required`, or RLS text → 403 permission sentence; else 400.

`flutter analyze` after this step: no issues. The app was not started.

### 30 September 2026 — investigation only, no code changes

Reported the customer-list N+1 and the email desync described above. No optimization and no Auth email sync was implemented.

---

## Constraints for the next chat

- Do not upgrade Flutter or rewrite the app.
- Do not put the Supabase secret in Flutter.
- Do not execute SQL, migrations, or `migrateCustomerAuthUsers.js` unless the user explicitly asks.
- Do not edit `001_initial_schema.sql`.
- Do not `FORCE ROW LEVEL SECURITY`.
- Do not delete Express routes or the bridge unless asked.
- Do not change Express or RPC behavior to make the 4 failing tests pass.
- Do not optimize the customer list or sync Auth emails unless asked. Both are known and already explained.
- Do not invent a customer get-by-id in Flutter.
- Screens should keep going through `AdminService` / `CustomerService`.
- `flutter analyze` was clean after Phase 6. The phone is not running that code until a new debug APK is built and installed.
- Backend tests need `required_permissions: ["all"]` because `.env` is ignored by the sandbox. Flutter builds that touch Gradle or the engine stamp also need to run outside the sandbox with `HOME` and `GRADLE_USER_HOME` set as above.

## Suggested first instruction

Read `/Users/apple/Desktop/hydra-care/HANDOFF.md` and treat it as the source of truth for project history. Do not invent applied migrations, device state, or unfinished work. The phone is still on the pre-Supabase APK. Customer-list slowness and email desync are known and were not fixed.
