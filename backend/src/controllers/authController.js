import { z } from 'zod';
import { AppError, catchAsync } from '../middleware/errorHandler.js';
import * as authService from '../services/authService.js';

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export const loginHandler = catchAsync(async (req, res) => {
  const { email, password } = req.body;
  const result = await authService.login(email, password);
  res.json({ success: true, data: result });
});

export const supabaseLoginHandler = catchAsync(async (req, res) => {
  const header = req.headers.authorization;

  if (typeof header !== 'string' || !header.startsWith('Bearer ')) {
    throw new AppError('Authentication required', 401);
  }

  const accessToken = header.slice('Bearer '.length).trim();

  if (!accessToken) {
    throw new AppError('Authentication required', 401);
  }

  const result = await authService.supabaseLogin(accessToken);
  res.json({ success: true, data: result });
});
