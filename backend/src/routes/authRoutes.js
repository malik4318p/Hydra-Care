import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { loginHandler, loginSchema, supabaseLoginHandler } from '../controllers/authController.js';

const router = Router();

router.post('/login', validate(loginSchema), loginHandler);
router.post('/supabase-login', supabaseLoginHandler);

export default router;
