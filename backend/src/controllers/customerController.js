import { z } from 'zod';
import { catchAsync } from '../middleware/errorHandler.js';
import * as customerService from '../services/customerService.js';

export const idParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export const createCustomerSchema = z.object({
  name: z.string().min(1),
  phone: z.string().min(1),
  email: z.string().email(),
  password: z.string().min(6, 'Password must be at least 6 characters'),
  address: z.string().min(1),
});

export const updateCustomerSchema = z.object({
  name: z.string().min(1).optional(),
  phone: z.string().min(1).optional(),
  email: z.string().email().optional(),
  address: z.string().min(1).optional(),
});

export const createCustomer = catchAsync(async (req, res) => {
  const customer = await customerService.createCustomer(req.body);
  res.status(201).json({ success: true, data: customer });
});

export const listCustomers = catchAsync(async (req, res) => {
  const customers = await customerService.listCustomers();
  res.json({ success: true, data: customers });
});

export const getCustomer = catchAsync(async (req, res) => {
  const customer = await customerService.getCustomerById(Number(req.params.id));
  res.json({ success: true, data: customer });
});

export const updateCustomer = catchAsync(async (req, res) => {
  const customer = await customerService.updateCustomer(Number(req.params.id), req.body);
  res.json({ success: true, data: customer });
});

export const deleteCustomer = catchAsync(async (req, res) => {
  await customerService.deleteCustomer(Number(req.params.id));
  res.json({ success: true, data: null });
});

export const getMyProfile = catchAsync(async (req, res) => {
  const customer = await customerService.getCustomerByUserId(req.user.userId);
  res.json({ success: true, data: customer });
});

export const getCustomerBalance = catchAsync(async (req, res) => {
  const balance = await customerService.getCustomerBalance(Number(req.params.id));
  res.json({ success: true, data: balance });
});

export const getMyBalance = catchAsync(async (req, res) => {
  const customer = await customerService.getCustomerByUserId(req.user.userId);
  const balance = await customerService.getCustomerBalance(customer.id);
  res.json({ success: true, data: balance });
});

export const getCustomerSummary = catchAsync(async (req, res) => {
  const summary = await customerService.getCustomerSummary(Number(req.params.id));
  res.json({ success: true, data: summary });
});

export const getMySummary = catchAsync(async (req, res) => {
  const customer = await customerService.getCustomerByUserId(req.user.userId);
  const summary = await customerService.getCustomerSummary(customer.id);
  res.json({ success: true, data: summary });
});
