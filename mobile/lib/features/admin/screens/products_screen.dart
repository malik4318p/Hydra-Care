import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/product.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final products = await widget.adminService.listProducts();
      if (!mounted) return;
      setState(() => _products = products);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openForm({Product? product}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateProductScreen(
          adminService: widget.adminService,
          product: product,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(product == null ? 'Product added.' : 'Product updated.')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          TextButton(onPressed: () => _openForm(), child: const Text('Add')),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading products...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _products.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 24),
                            EmptyView(message: 'No products yet. Tap Add to create one.'),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            final typeLabel = product.type == 'refill' ? 'Refill' : 'Bottle';
                            return Card(
                              child: ListTile(
                                title: Text(product.name),
                                subtitle: Text(
                                  product.active ? typeLabel : '$typeLabel · Inactive',
                                ),
                                trailing: Text(formatMoney(product.currentPrice)),
                                onTap: () => _openForm(product: product),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _CreateProductScreen extends StatefulWidget {
  const _CreateProductScreen({required this.adminService, this.product});

  final AdminService adminService;
  final Product? product;

  @override
  State<_CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<_CreateProductScreen> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  String _type = 'bottle';
  bool _active = true;
  bool _loading = false;
  String? _error;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product == null) return;
    _nameController.text = product.name;
    _priceController.text = product.currentPrice.toString();
    _type = product.type;
    _active = product.active;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final price = num.tryParse(_priceController.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a price greater than 0.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final existing = widget.product;
      if (existing == null) {
        await widget.adminService.createProduct(
          name: name,
          type: _type,
          currentPrice: price,
        );
      } else {
        await widget.adminService.updateProduct(
          id: existing.id,
          name: name,
          type: _type,
          currentPrice: price,
          active: _active,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _editing ? 'Could not update the product.' : 'Could not add the product.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'Add product')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AppTextField(controller: _nameController, label: 'Name'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'bottle', child: Text('Bottle')),
                DropdownMenuItem(value: 'refill', child: Text('Refill')),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value != null) setState(() => _type = value);
                    },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _priceController,
              label: 'Price',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: _loading ? null : (value) => setState(() => _active = value),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: _editing ? 'Save changes' : 'Save product',
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
