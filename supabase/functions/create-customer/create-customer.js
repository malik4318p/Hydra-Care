const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export class CustomerCreateError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'CustomerCreateError';
    this.status = status;
  }
}

export function authCreateAttributes(email, password) {
  return {
    email,
    password,
    email_confirm: true,
  };
}

export function applicationUserInsert(fields) {
  return {
    name: fields.name,
    phone: fields.phone,
    email: fields.email,
    password_hash: null,
    role: 'customer',
    auth_user_id: fields.authUserId,
  };
}

export function mapAuthCreateError(error) {
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

  return { status: 400, message: 'The customer could not be created.' };
}

function fail(status, message) {
  return { status, body: { success: false, message } };
}

function ok(data) {
  return { status: 201, body: { success: true, data } };
}

function bearerToken(authorization) {
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
    return null;
  }
  const token = authorization.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

function requiredText(value, maxLength) {
  if (typeof value !== 'string') {
    return null;
  }
  const text = value.trim();
  if (text.length === 0 || text.length > maxLength) {
    return null;
  }
  return text;
}

function requestedEmail(value) {
  const email = requiredText(value, 255);
  if (!email || !EMAIL_PATTERN.test(email)) {
    return null;
  }
  return email;
}

function requestedPassword(value) {
  if (typeof value !== 'string' || value.length < 6) {
    return null;
  }
  return value;
}

export async function createCustomerAccount(input) {
  try {
    return await performCreateCustomer(input);
  } catch (error) {
    if (error instanceof CustomerCreateError) {
      return fail(error.status, error.message);
    }
    return fail(500, 'The customer could not be created.');
  }
}

async function performCreateCustomer({ authorization, payload, gateway }) {
  const token = bearerToken(authorization);
  if (!token) {
    return fail(401, 'Authentication required');
  }

  let callerAuthId;
  try {
    callerAuthId = await gateway.verifiedUserId(token);
  } catch (error) {
    if (error instanceof CustomerCreateError) {
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

  const name = requiredText(payload?.name, 255);
  const phone = requiredText(payload?.phone, 20);
  const email = requestedEmail(payload?.email);
  const address = requiredText(payload?.address, 500);
  const password = requestedPassword(payload?.password);
  const emailText = typeof payload?.email === 'string' ? payload.email.trim() : '';

  if (!name || !phone || emailText.length === 0 || !address) {
    return fail(400, 'Name, phone, email, and address are required.');
  }
  if (!email) {
    return fail(400, 'Enter a valid email.');
  }
  if (!password) {
    return fail(400, 'Password must be at least 6 characters.');
  }

  if (await gateway.emailTaken(email)) {
    return fail(409, 'A user with this email already exists');
  }

  let authUser;
  try {
    authUser = await gateway.createAuthUser(email, password);
  } catch (error) {
    if (error instanceof CustomerCreateError) {
      return fail(error.status, error.message);
    }
    const mapped = mapAuthCreateError(error);
    return fail(mapped.status, mapped.message);
  }

  if (!authUser || typeof authUser.id !== 'string' || !UUID_PATTERN.test(authUser.id)) {
    return fail(500, 'The customer could not be created.');
  }
  if (typeof authUser.email !== 'string' || authUser.email.length === 0) {
    await removeAuthUser(gateway, authUser.id);
    return fail(500, 'The customer could not be created.');
  }

  let applicationUser;
  try {
    applicationUser = await gateway.insertApplicationUser(
      applicationUserInsert({
        name,
        phone,
        email: authUser.email,
        authUserId: authUser.id,
      })
    );
  } catch (error) {
    await removeAuthUser(gateway, authUser.id);
    if (error instanceof CustomerCreateError) {
      return fail(error.status, error.message);
    }
    const mapped = mapAuthCreateError(error);
    return fail(mapped.status, mapped.message);
  }

  let customer;
  try {
    customer = await gateway.insertCustomer({
      userId: applicationUser.id,
      address,
    });
  } catch (error) {
    await removeApplicationUser(gateway, applicationUser.id);
    await removeAuthUser(gateway, authUser.id);
    if (error instanceof CustomerCreateError) {
      return fail(error.status, error.message);
    }
    return fail(500, 'The customer could not be created.');
  }

  return ok({
    id: customer.id,
    user_id: applicationUser.id,
    name: applicationUser.name,
    phone: applicationUser.phone,
    email: applicationUser.email,
    role: 'customer',
    address: customer.address,
    created_at: customer.createdAt,
    updated_at: customer.updatedAt,
  });
}

async function removeAuthUser(gateway, authUserId) {
  try {
    await gateway.deleteAuthUser(authUserId);
  } catch {
    // The caller still receives a failure.
  }
}

async function removeApplicationUser(gateway, userId) {
  try {
    await gateway.deleteApplicationUser(userId);
  } catch {
    // The caller still receives a failure.
  }
}
