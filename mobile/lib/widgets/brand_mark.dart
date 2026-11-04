import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Placeholder until the approved HydraCure logo artwork is supplied.
    return Icon(
      Icons.water_drop_outlined,
      size: size,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
