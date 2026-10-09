const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export class EmailChangeError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'EmailChangeError';
    this.status = status;
  }
}

export function authEmailUpdate(email) {
  return { email };
}

export function mapAuthUpdateError(error) {
  const message = typeof error?.message === 'string' ? error.message : '';
  const code = typeof error?.code === 'string' ? error.code : '';
  const status = Number(error?.status ?? error?.statusCode);

  if (
    code === 'email_exists' ||
    code === '23505' ||
    status === 422 ||
    /already been registered|already exists|duplicate key|unique constraint/i.test(message)
  ) {
    return { status: 409, message: 'A user with this email already exists' };
  }

  return { status: 400, message: 'The email could not be changed.' };
}

function fail(status, message) {
  return { status, body: { success: false, message } };
}

function ok(data) {
  return { status: 200, body: { success: true, data } };
}

function bearerToken(authorization) {
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
    return null;
  }
  const token = authorization.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

function customerId(value) {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === 'string' && /^[1-9]\d*$/.test(value)) {
    const parsed = Number(value);
    if (Number.isSafeInteger(parsed)) {
      return parsed;
    }
  }
  return null;
}

function requestedEmail(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const email = value.trim();
  if (email.length === 0 || email.length > 255 || !EMAIL_PATTERN.test(email)) {
    return null;
  }
  return email;
}

export async function changeCustomerEmail(input) {
  try {
    return await performCustomerEmailChange(input);
  } catch (error) {
    if (error instanceof EmailChangeError) {
      return fail(error.status, error.message);
    }
    return fail(500, 'The email could not be changed.');
  }
}

async function performCustomerEmailChange({ authorization, payload, gateway }) {
  const token = bearerToken(authorization);
  if (!token) {
    return fail(401, 'Authentication required');
  }

  let callerAuthId;
  try {
    callerAuthId = await gateway.verifiedUserId(token);
  } catch (error) {
    if (error instanceof EmailChangeError) {
      return fail(error.status, error.message);
    }
    return fail(401, 'Invalid or expired token');
  }

  if (typeof callerAuthId !== 'string' || !UUID_PATTERN.test(callerAuthId)) {
    return fail(401, 'Invalid or expired token');
  }

  const caller = await gateway.applicationUserByAuthId(callerAuthId);
  if (!caller) {
    return fail(401, 'No application user is linked to this account');
  }
  if (caller.role !== 'admin') {
    return fail(403, 'You do not have permission to perform this action');
  }

  const id = customerId(payload?.customer_id);
  const email = requestedEmail(payload?.email);
  if (!id) {
    return fail(400, 'A valid customer is required.');
  }
  if (!email) {
    return fail(400, 'Enter a valid email.');
  }

  const target = await gateway.customerAccount(id);
  if (!target) {
    return fail(404, 'Customer not found');
  }
  if (target.role !== 'customer') {
    return fail(403, 'You do not have permission to perform this action');
  }
  if (typeof target.authUserId !== 'string' || !UUID_PATTERN.test(target.authUserId)) {
    return fail(400, 'This customer is not linked to a sign-in account.');
  }

  const authUser = await gateway.authUser(target.authUserId);
  if (!authUser || authUser.id !== target.authUserId || typeof authUser.email !== 'string') {
    return fail(400, 'This customer is not linked to a sign-in account.');
  }

  if (authUser.email === email && target.email === email) {
    return ok({
      customer_id: target.customerId,
      user_id: target.userId,
      email,
      auth_user_id: target.authUserId,
      unchanged: true,
    });
  }

  if (await gateway.emailTaken(email, target.userId)) {
    return fail(409, 'A user with this email already exists');
  }

  let updated;
  try {
    updated = await gateway.updateAuthEmail(target.authUserId, email);
  } catch (error) {
    if (error instanceof EmailChangeError) {
      return fail(error.status, error.message);
    }
    const mapped = mapAuthUpdateError(error);
    return fail(mapped.status, mapped.message);
  }

  if (!updated || updated.email !== email) {
    await revertAuthEmail(gateway, target.authUserId, authUser.email);
    return fail(500, 'The email could not be synchronized.');
  }

  let syncedEmail;
  try {
    syncedEmail = await gateway.publicEmail(target.userId);
  } catch (error) {
    await revertAuthEmail(gateway, target.authUserId, authUser.email);
    if (error instanceof EmailChangeError) {
      return fail(error.status, error.message);
    }
    return fail(500, 'The email could not be synchronized.');
  }

  if (syncedEmail !== email) {
    await revertAuthEmail(gateway, target.authUserId, authUser.email);
    return fail(500, 'The email could not be synchronized.');
  }

  let linked;
  try {
    linked = await gateway.customerAccount(id);
  } catch (error) {
    await revertAuthEmail(gateway, target.authUserId, authUser.email);
    if (error instanceof EmailChangeError) {
      return fail(error.status, error.message);
    }
    return fail(500, 'The email could not be synchronized.');
  }

  if (!linked || linked.authUserId !== target.authUserId || linked.email !== email) {
    await revertAuthEmail(gateway, target.authUserId, authUser.email);
    return fail(500, 'The email could not be synchronized.');
  }

  return ok({
    customer_id: target.customerId,
    user_id: target.userId,
    email,
    auth_user_id: target.authUserId,
    unchanged: false,
  });
}

async function revertAuthEmail(gateway, authUserId, previousEmail) {
  try {
    await gateway.updateAuthEmail(authUserId, previousEmail);
  } catch {
    // The caller still receives a failure. Do not report success.
  }
}
