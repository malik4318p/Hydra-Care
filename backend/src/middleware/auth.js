import jwt from 'jsonwebtoken';
import env from '../config/env.js';
import { AppError } from './errorHandler.js';

export function auth(req, res, next) {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    return next(new AppError('Authentication required', 401));
  }

  const token = header.slice('Bearer '.length);

  try {
    const payload = jwt.verify(token, env.jwtSecret);
    req.user = { userId: payload.userId, role: payload.role };
    next();
  } catch {
    next(new AppError('Invalid or expired token', 401));
  }
}
