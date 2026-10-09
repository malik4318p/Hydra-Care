import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { authorize } from '../middleware/authorize.js';
import { validate } from '../middleware/validate.js';
import {
  createPayment,
  createPaymentSchema,
  deletePayment,
  getPayment,
  idParamSchema,
  listPayments,
  listPaymentsQuerySchema,
  updatePayment,
  updatePaymentSchema,
} from '../controllers/paymentController.js';

const router = Router();

router.use(auth);

router.get('/', validate(listPaymentsQuerySchema, 'query'), listPayments);
router.get('/:id', validate(idParamSchema, 'params'), getPayment);
router.post('/', authorize('admin'), validate(createPaymentSchema), createPayment);
router.put(
  '/:id',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  validate(updatePaymentSchema),
  updatePayment
);
router.delete('/:id', authorize('admin'), validate(idParamSchema, 'params'), deletePayment);

export default router;
