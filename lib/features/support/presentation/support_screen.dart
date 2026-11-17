import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/section_card.dart';
import '../../authentication/providers/auth_controller.dart';
import 'widgets/business_contact_card.dart';

/// Customer support.
///
/// Reachable without signing in - someone who cannot get into their account is
/// exactly who needs support most - so everything here comes from the
/// unauthenticated `GET /public/business-contact`.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppFeedback.showError(context, 'Could not open that link.');
      }
    } on Object {
      if (context.mounted) AppFeedback.showError(context, 'That link is not valid.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contactState = ref.watch(businessContactProvider);
    final isSignedIn = ref.watch(authControllerProvider).isAuthenticated;

    /// The contact answer names the real number rather than saying "see the
    /// card above", because this question is the one a customer opens when the
    /// card has not loaded - they are on a train with one bar of signal. The
    /// number comes from the operator's own record, so there is no hardcoded
    /// number here to go stale; when it has not loaded, the answer says where
    /// to find it instead of inventing one.
    final contact = contactState.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );

    final contactAnswer = contact == null
        ? 'Our phone number and email address are at the top of this screen, '
              'under "Contact the operator". You can also tap Contact on any '
              'booking to call us about that specific trip.\n\n'
              'We are still loading those details - pull down to refresh.'
        : [
            if (contact.hasPhone)
              'Call us on ${contact.callNumber}. ${contact.supportHours ?? 'We answer during our published support hours.'}',
            if (contact.hasWhatsapp) 'Message us on WhatsApp at ${contact.whatsappNumber}.',
            if (contact.hasEmail) 'Email us at ${contact.emailAddress}.',
            'You can reach all of these from the card at the top of this screen, '
                'or by tapping Contact on any booking - that way we can see which '
                'trip you are calling about.',
            'Quote your booking reference when you get through. It is the '
                'fastest way for us to find your trip.',
          ].join('\n\n');

    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(businessContactProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            AppSpacing.md,
            AppSpacing.pageGutter,
            AppSpacing.xxl,
          ),
          children: [
            const BusinessContactCard(
              title: 'Contact the operator',
              subtitle: 'For questions about a booking, a fare, or lost property.',
            ),
            const SizedBox(height: AppSpacing.lg),

            if (isSignedIn) ...[
              SectionCard(
                title: 'Before you call',
                icon: Icons.lightbulb_outline_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Have your booking reference to hand - it is on the booking details '
                      'screen and starts with TX. It is the quickest way for the operator to '
                      'find your trip.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SecondaryButton(
                      label: 'Open my bookings',
                      icon: Icons.receipt_long_outlined,
                      onPressed: () => context.push(AppRoutes.bookings),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            SectionCard(
              title: 'Common questions',
              icon: Icons.help_outline_rounded,
              child: Column(
                children: [
                  _Faq(
                    question: 'How do I book a trip?',
                    answer:
                        'Five steps, in this order.\n\n'
                        '1. On the home screen, choose your booking date and your return '
                        'date. The dates come first because which vehicles exist at all '
                        'depends on them - the fleet is held day by day.\n\n'
                        '2. Set your pickup point. We fill it in from your location if you '
                        'have allowed it; tap it to search for an address or drop a pin '
                        'instead.\n\n'
                        '3. Tap "Where to?" and choose your drop location the same way.\n\n'
                        '4. Tap "Find available vehicles". You see only the vehicles that '
                        'are genuinely free for your dates. Tap one to see its photographs, '
                        'specification, daily rate and total.\n\n'
                        '5. Check the fare breakdown, choose Online Payment or Cash on Pay, '
                        'and confirm. Your booking reference appears straight away - keep '
                        'it for any questions.',
                  ),
                  _Faq(
                    question: 'How do I contact ${AppConfig.serviceName}?',
                    answer: contactAnswer,
                  ),
                  _Faq(
                    question: 'Can I cancel after booking?',
                    answer:
                        'Yes, up until the trip starts. Cancelling before a driver is assigned '
                        'is always free. After that a cancellation fee may apply, and the exact '
                        'amount is shown before you confirm.',
                  ),
                  _Faq(
                    question: 'How do I change my mobile number?',
                    answer:
                        'Profile, then Personal details. We send a code to the new number to '
                        'confirm it is yours before making the change.',
                  ),
                  _Faq(
                    question: 'I did not receive my one-time code.',
                    answer:
                        'Sign-in codes are emailed, not texted - they go to the email '
                        'address registered against your mobile number, so check that '
                        'inbox rather than your messages. Look in spam or promotions '
                        'too; the first one from us sometimes lands there.\n\n'
                        'If it still has not arrived, wait for the resend timer and '
                        'request a new one. Each new code replaces the last, so use the '
                        'most recent email. If codes never arrive, contact us using the '
                        'details above and we will check the address on your account.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            contactState.maybeWhen(
              data: (contact) {
                if (!contact.hasTerms && !contact.hasPrivacy) {
                  return const SizedBox.shrink();
                }

                return SectionCard(
                  title: 'Legal',
                  icon: Icons.gavel_rounded,
                  child: Column(
                    children: [
                      if (contact.hasTerms)
                        ListTile(
                          onTap: () => _openUrl(context, contact.termsUrl!),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined, size: 20),
                          title: const Text('Terms of service'),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                        ),
                      if (contact.hasPrivacy)
                        ListTile(
                          onTap: () => _openUrl(context, contact.privacyUrl!),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.privacy_tip_outlined, size: 20),
                          title: const Text('Privacy policy'),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                        ),
                      if ((contact.websiteUrl ?? '').isNotEmpty)
                        ListTile(
                          onTap: () => _openUrl(context, contact.websiteUrl!),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.language_rounded, size: 20),
                          title: const Text('Website'),
                          trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                        ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible question. [ExpansionTile] keeps the list short enough to scan.
class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      // Strips the default dividers so these sit flush inside the card.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(question, style: theme.textTheme.titleSmall),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(answer, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
