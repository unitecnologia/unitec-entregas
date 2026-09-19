import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

/// Pad compacto de assinatura (opcional na conclusão de entrega).
class AssinaturaPad extends StatefulWidget {
  const AssinaturaPad({
    super.key,
    required this.controller,
    this.height = 128,
  });

  final SignatureController controller;
  final double height;

  @override
  State<AssinaturaPad> createState() => _AssinaturaPadState();
}

class _AssinaturaPadState extends State<AssinaturaPad> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Assinatura',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                widget.controller.clear();
                setState(() {});
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Limpar'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF94A3B8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Signature(
            controller: widget.controller,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Assine com o dedo',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
