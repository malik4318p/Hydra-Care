import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { authorize } from '../middleware/authorize.js';
import { validate } from '../middleware/validate.js';
import {
  createProduct,
  createProductSchema,
  deleteProduct,
  getProduct,
  idParamSchema,
  listProducts,
  listProductsQuerySchema,
  updateProduct,
  updateProductSchema,
} from '../controllers/productController.js';

const router = Router();

router.use(auth);

router.get('/', validate(listProductsQuerySchema, 'query'), listProducts);
router.get('/:id', validate(idParamSchema, 'params'), getProduct);
router.post('/', authorize('admin'), validate(createProductSchema), createProduct);
router.put(
  '/:id',
  authorize('admin'),
  validate(idParamSchema, 'params'),
  validate(updateProductSchema),
  updateProduct
);
router.delete('/:id', authorize('admin'), validate(idParamSchema, 'params'), deleteProduct);

export default router;
