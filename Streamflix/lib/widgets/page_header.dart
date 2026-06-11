import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Inline page header used inside the navigation shell (so pages don't carry
/// their own AppBar, which would stack under the desktop top bar). Shows a
/// back button only when there is something to pop.
class PageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const PageHeader({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 4),
        child: Row(
          children: [
            if (canPop)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
