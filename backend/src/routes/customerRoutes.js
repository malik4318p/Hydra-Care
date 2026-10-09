import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { authorize } from '../middleware/authorize.js';
import { validate } from '../middleware/validate.js';
import {
  createCustomer,
  createCustomerSchema,
  deleteCustomer,
  getCustomer,
  getCustomerBalance,
  getCustomerSummary,
  getMyBalance,
  getMyProfile,
  getMySummary,
  idParamSchema,
  listCustomers,
  updateCustomer,
  updateCustomerSchema,
} from '../controllers/customerController.js';

const router = Router();

router.use(auth);

// These literal "/me..." routes must be registered before "/:id" routes,
// otherwise Express would match "me" as the :id parameter.
router.get('/me', authorize('customer'), getMyProfile);
router.get('/me/balance', authorize('customer'), getMyBalance);
router.get('/me/summary', authorize('customer'), getMySummary);

router.post('/', authorize('admin'), validate(createCustomerSchema), createCustomer);
router.get('/', authorize('admin'), listCustomers);

router.get(
  '/:id/balance',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  getCustomerBalance
);
router.get(
  '/:id/summary',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  getCustomerSummary
);
router.get('/:id', authorize('admin'), validate(idParamSchema, 'params'), getCustomer);
router.put(
  '/:id',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  validate(updateCustomerSchema),
  updateCustomer
);
router.delete('/:id', authorize('admin'), validate(idParamSchema, 'params'), deleteCustomer);

export default router;
