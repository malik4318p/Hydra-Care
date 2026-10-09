import { z } from 'zod';
import { catchAsync, AppError } from '../middleware/errorHandler.js';
import * as transactionService from '../services/transactionService.js';
import * as customerService from '../services/customerService.js';

export const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export const listTransactionsQuerySchema = z.object({
  customer_id: z.coerce.number().int().positive().optional(),
});

export const createTransactionSchema = z.object({
  customer_id: z.number().int().positive(),
  product_id: z.number().int().positive(),
  quantity: z.number().int().positive(),
  unit_price: z.number().positive().optional(),
  notes: z.string().optional(),
});

export const updateTransactionSchema = z.object({
  product_id: z.number().int().positive().optional(),
  quantity: z.number().int().positive().optional(),
  unit_price: z.number().positive().optional(),
  notes: z.string().optional(),
});

export const createTransaction = catchAsync(async (req, res) => {
  const transaction = await transactionService.createTransaction(req.body, req.user.userId);
  res.status(201).json({ success: true, data: transaction });
});

export const listTransactions = catchAsync(async (req, res) => {
  let customerId;

  if (req.user.role === 'admin') {
    customerId = req.query.customer_id;
  } else {
    const customer = await customerService.getCustomerByUserId(req.user.userId);
    customerId = customer.id;
  }

  const transactions = await transactionService.listTransactions({ customerId });
  res.json({ success: true, data: transactions });
});

export const getTransaction = catchAsync(async (req, res) => {
  const transaction = await transactionService.getTransactionById(Number(req.params.id));

  if (req.user.role !== 'admin') {
    const customer = await customerService.getCustomerByUserId(req.user.userId);
    if (transaction.customer_id !== customer.id) {
      throw new AppError('Transaction not found', 404);
    }
  }

  res.json({ success: true, data: transaction });
});

export const updateTransaction = catchAsync(async (req, res) => {
  const transaction = await transactionService.updateTransaction(Number(req.params.id), req.body);
  res.json({ success: true, data: transaction });
});

export const deleteTransaction = catchAsync(async (req, res) => {
  await transactionService.deleteTransaction(Number(req.params.id));
  res.json({ success: true, data: null });
});
