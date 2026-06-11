import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final String hint;

  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.autofocus = false,
    this.hint = 'Search movies & shows',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.mutedForeground),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded, color: AppColors.mutedForeground),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}
