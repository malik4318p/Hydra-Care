import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { authorize } from '../middleware/authorize.js';
import { validate } from '../middleware/validate.js';
import {
  createTransaction,
  createTransactionSchema,
  deleteTransaction,
  getTransaction,
  idParamSchema,
  listTransactions,
  listTransactionsQuerySchema,
  updateTransaction,
  updateTransactionSchema,
} from '../controllers/transactionController.js';

const router = Router();

router.use(auth);

router.get('/', validate(listTransactionsQuerySchema, 'query'), listTransactions);
router.get('/:id', validate(idParamSchema, 'params'), getTransaction);
router.post('/', authorize('admin'), validate(createTransactionSchema), createTransaction);
router.put(
  '/:id',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  validate(updateTransactionSchema),
  updateTransaction
);
router.delete('/:id', authorize('admin'), validate(idParamSchema, 'params'), deleteTransaction);

export default router;
