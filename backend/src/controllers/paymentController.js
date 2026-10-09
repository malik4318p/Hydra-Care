import { z } from 'zod';
import { catchAsync, AppError } from '../middleware/errorHandler.js';
import * as paymentService from '../services/paymentService.js';
import * as customerService from '../services/customerService.js';

export const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export const listPaymentsQuerySchema = z.object({
  customer_id: z.coerce.number().int().positive().optional(),
});

export const createPaymentSchema = z.object({
  customer_id: z.number().int().positive(),
  transaction_id: z.number().int().positive().nullable().optional(),
  amount: z.number().positive(),
  payment_method: z.string().min(1),
  notes: z.string().optional(),
});

export const updatePaymentSchema = z.object({
  amount: z.number().positive().optional(),
  payment_method: z.string().min(1).optional(),
  transaction_id: z.number().int().positive().nullable().optional(),
  notes: z.string().optional(),
});

export const createPayment = catchAsync(async (req, res) => {
  const payment = await paymentService.createPayment(req.body, req.user.userId);
  res.status(201).json({ success: true, data: payment });
});

export const listPayments = catchAsync(async (req, res) => {
  let customerId;

  if (req.user.role === 'admin') {
    customerId = req.query.customer_id;
  } else {
    const customer = await customerService.getCustomerByUserId(req.user.userId);
    customerId = customer.id;
  }

  const payments = await paymentService.listPayments({ customerId });
  res.json({ success: true, data: payments });
});

export const getPayment = catchAsync(async (req, res) => {
  const payment = await paymentService.getPaymentById(Number(req.params.id));

  if (req.user.role !== 'admin') {
    const customer = await customerService.getCustomerByUserId(req.user.userId);
    if (payment.customer_id !== customer.id) {
      throw new AppError('Payment not found', 404);
    }
  }

  res.json({ success: true, data: payment });
});

export const updatePayment = catchAsync(async (req, res) => {
  const payment = await paymentService.updatePayment(Number(req.params.id), req.body);
  res.json({ success: true, data: payment });
});

export const deletePayment = catchAsync(async (req, res) => {
  await paymentService.deletePayment(Number(req.params.id));
  res.json({ success: true, data: null });
});
