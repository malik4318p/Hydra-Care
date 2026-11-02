const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const INVALID_OPTIONAL_VALUE = Symbol('invalid optional value');

export class CustomerCreateError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'CustomerCreateError';
    this.status = status;
  }
}

export function applicationUserInsert(fields) {
  return {
    name: fields.name,
    phone: fields.phone,
    email: fields.email,
    password_hash: null,
    role: 'customer',
    auth_user_id: null,
  };
}

export function mapCustomerInsertError(error) {
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

function optionalText(value, maxLength) {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    return INVALID_OPTIONAL_VALUE;
  }

  const text = value.trim();
  if (text.length === 0) {
    return null;
  }
  if (text.length > maxLength) {
    return INVALID_OPTIONAL_VALUE;
  }
  return text;
}

function optionalEmail(value) {
  const email = optionalText(value, 255);
  if (email === null || email === INVALID_OPTIONAL_VALUE) {
    return email;
  }
  return EMAIL_PATTERN.test(email) ? email : INVALID_OPTIONAL_VALUE;
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
  const email = optionalEmail(payload?.email);
  const address = optionalText(payload?.address, 500);

  if (!name || !phone) {
    return fail(400, 'Name and phone are required.');
  }
  if (email === INVALID_OPTIONAL_VALUE) {
    return fail(400, 'Enter a valid email.');
  }
  if (address === INVALID_OPTIONAL_VALUE) {
    return fail(400, 'Enter a valid address.');
  }

  if (email !== null && (await gateway.emailTaken(email))) {
    return fail(409, 'A user with this email already exists');
  }

  let applicationUser;
  try {
    applicationUser = await gateway.insertApplicationUser(
      applicationUserInsert({
        name,
        phone,
        email,
      })
    );
  } catch (error) {
    if (error instanceof CustomerCreateError) {
      return fail(error.status, error.message);
    }
    const mapped = mapCustomerInsertError(error);
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
    auth_user_id: null,
    address: customer.address,
    created_at: customer.createdAt,
    updated_at: customer.updatedAt,
  });
}

async function removeApplicationUser(gateway, userId) {
  try {
    await gateway.deleteApplicationUser(userId);
  } catch {
    // The caller still receives a failure.
  }
}
