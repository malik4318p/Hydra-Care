import { z } from 'zod';
import { catchAsync } from '../middleware/errorHandler.js';
import * as productService from '../services/productService.js';

export const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export const createProductSchema = z.object({
  name: z.string().min(1),
  type: z.enum(['bottle', 'refill']),
  current_price: z.number().positive(),
});

export const updateProductSchema = z.object({
  name: z.string().min(1).optional(),
  type: z.enum(['bottle', 'refill']).optional(),
  current_price: z.number().positive().optional(),
  active: z.boolean().optional(),
});

export const listProductsQuerySchema = z.object({
  active: z
    .enum(['true', 'false'])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === 'true')),
});

export const createProduct = catchAsync(async (req, res) => {
  const product = await productService.createProduct(req.body);
  res.status(201).json({ success: true, data: product });
});

export const listProducts = catchAsync(async (req, res) => {
  const products = await productService.listProducts(req.query.active);
  res.json({ success: true, data: products });
});

export const getProduct = catchAsync(async (req, res) => {
  const product = await productService.getProductById(Number(req.params.id));
  res.json({ success: true, data: product });
});

export const updateProduct = catchAsync(async (req, res) => {
  const product = await productService.updateProduct(Number(req.params.id), req.body);
  res.json({ success: true, data: product });
});

export const deleteProduct = catchAsync(async (req, res) => {
  await productService.deleteProduct(Number(req.params.id));
  res.json({ success: true, data: null });
});
