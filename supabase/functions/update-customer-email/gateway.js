import { EmailChangeError, authEmailUpdate } from './email-change.js';

function fail(status, message) {
  throw new EmailChangeError(status, message);
}

export function createEmailChangeGateway(admin) {
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
        fail(500, 'The email could not be changed.');
      }
      if (!data) {
        return null;
      }
      return { id: data.id, role: data.role };
    },

    async customerAccount(customerId) {
      const { data, error } = await admin
        .from('customers')
        .select('id, user_id, users!fk_customers_user(id, email, role, auth_user_id)')
        .eq('id', customerId)
        .maybeSingle();

      if (error) {
        fail(500, 'The email could not be changed.');
      }
      if (!data) {
        return null;
      }

      const user = data.users;
      if (!user || Array.isArray(user)) {
        fail(500, 'The email could not be changed.');
      }

      return {
        customerId: data.id,
        userId: user.id,
        email: user.email,
        role: user.role,
        authUserId: user.auth_user_id,
      };
    },

    async authUser(authUserId) {
      const { data, error } = await admin.auth.admin.getUserById(authUserId);
      if (error || !data?.user) {
        return null;
      }
      return { id: data.user.id, email: data.user.email };
    },

    async emailTaken(email, userId) {
      const { data, error } = await admin
        .from('users')
        .select('id')
        .eq('email', email)
        .neq('id', userId)
        .limit(1);

      if (error) {
        fail(500, 'The email could not be changed.');
      }
      return Array.isArray(data) && data.length > 0;
    },

    async updateAuthEmail(authUserId, email) {
      const { data, error } = await admin.auth.admin.updateUserById(
        authUserId,
        authEmailUpdate(email)
      );

      if (error) {
        throw error;
      }

      const stored = data?.user?.email;
      if (typeof stored !== 'string') {
        fail(500, 'The email could not be changed.');
      }
      return { email: stored };
    },

    async publicEmail(userId) {
      const { data, error } = await admin
        .from('users')
        .select('email')
        .eq('id', userId)
        .maybeSingle();

      if (error || !data || typeof data.email !== 'string') {
        fail(500, 'The email could not be synchronized.');
      }
      return data.email;
    },
  };
}
