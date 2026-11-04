import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/primary_button.dart';

/// First-run introduction. Shown once; the "seen" flag lives in prefs, so it
/// survives sign-out but not a reinstall.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.pin_drop_rounded,
      title: 'Tell us where you are going',
      body:
          'Set your pickup and destination on the map, or search for an address. '
          'We work out the route for you.',
    ),
    _OnboardingPage(
      icon: Icons.directions_car_filled_rounded,
      title: 'Pick the right vehicle',
      body:
          'Compare Mini, Sedan, SUV and Premium with the fare estimate for your '
          'exact trip before you commit.',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_rounded,
      title: 'Follow your ride',
      body:
          'Get the booking reference straight away, then updates as your driver '
          'is assigned, arrives and completes the trip.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(prefsStoreProvider).setOnboardingSeen();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  void _next() {
    if (_page >= _pages.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastPage = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageGutter,
                AppSpacing.lg,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  const AppLogo(size: 36),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'PP Travels',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  // Skip is always available: nobody should be forced through
                  // three slides to reach a login screen.
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _pages[index],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.pageGutter),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (index) {
                      final isActive = index == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 7,
                        width: isActive ? 24 : 7,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.amber
                              : theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: isLastPage ? 'Get started' : 'Next',
                    icon: isLastPage ? null : Icons.arrow_forward_rounded,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 160,
            width: 160,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, size: 72, color: AppColors.amberDark),
            ),
          ),
          const SizedBox(height: AppSpacing.huge),
          Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
