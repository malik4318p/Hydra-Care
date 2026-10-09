import { CustomerCreateError, authCreateAttributes } from './create-customer.js';

function fail(status, message) {
  throw new CustomerCreateError(status, message);
}

export function createCustomerGateway(admin) {
  return {
    async verifiedUserId(token) {
      const { data, error } = await admin.auth.getUser(token);
      if (error || !data?.user?.id) {
        fail(401, 'Invalid or expired token');
      }
      return data.user.id;
    },

    async applicationUserByAuthId(authUserId) {
      const { data, error } = await admin
        .from('users')
        .select('id, role')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

      if (error) {
        fail(500, 'The customer could not be created.');
      }
      if (!data) {
        return null;
      }
      return { id: data.id, role: data.role };
    },

    async emailTaken(email) {
      const { data, error } = await admin
        .from('users')
        .select('id')
        .eq('email', email)
        .limit(1);

      if (error) {
        fail(500, 'The customer could not be created.');
      }
      return Array.isArray(data) && data.length > 0;
    },

    async createAuthUser(email, password) {
      const { data, error } = await admin.auth.admin.createUser(
        authCreateAttributes(email, password)
      );

      if (error) {
        throw error;
      }

      return {
        id: data?.user?.id,
        email: data?.user?.email,
      };
    },

    async insertApplicationUser(row) {
      const { data, error } = await admin
        .from('users')
        .insert(row)
        .select('id, name, phone, email, role, auth_user_id, created_at, updated_at')
        .single();

      if (error) {
        throw error;
      }

      return {
        id: data.id,
        name: data.name,
        phone: data.phone,
        email: data.email,
        authUserId: data.auth_user_id,
      };
    },

    async insertCustomer({ userId, address }) {
      const { data, error } = await admin
        .from('customers')
        .insert({ user_id: userId, address })
        .select('id, user_id, address, created_at, updated_at')
        .single();

      if (error) {
        throw error;
      }

      return {
        id: data.id,
        address: data.address,
        createdAt: data.created_at,
        updatedAt: data.updated_at,
      };
    },

    async deleteApplicationUser(userId) {
      const customerDelete = await admin.from('customers').delete().eq('user_id', userId);
      if (customerDelete.error) {
        fail(500, 'The customer could not be created.');
      }
      const userDelete = await admin.from('users').delete().eq('id', userId);
      if (userDelete.error) {
        fail(500, 'The customer could not be created.');
      }
    },

    async deleteAuthUser(authUserId) {
      const { error } = await admin.auth.admin.deleteUser(authUserId);
      if (error) {
        throw error;
      }
    },
  };
}
