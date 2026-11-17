import '../../../core/config/app_config.dart';

/// The official business contact details, from `GET /public/business-contact`.
///
/// Everything here is fetched at runtime. Nothing in this app hardcodes an
/// operator's phone number or email, so an operator can change their support
/// line without shipping an update - and a white-labelled build needs no code
/// change at all.
class BusinessContact {
  const BusinessContact({
    required this.businessName,
    this.adminContactName,
    this.adminPhone,
    this.adminEmail,
    this.supportPhone,
    this.supportEmail,
    this.whatsappNumber,
    this.address,
    this.websiteUrl,
    this.termsUrl,
    this.privacyUrl,
    this.workingHours,
    this.supportHours,
  });

  final String businessName;
  final String? adminContactName;
  final String? adminPhone;
  final String? adminEmail;
  final String? supportPhone;
  final String? supportEmail;
  final String? whatsappNumber;
  final String? address;
  final String? websiteUrl;
  final String? termsUrl;
  final String? privacyUrl;
  final String? workingHours;
  final String? supportHours;

  factory BusinessContact.fromJson(Map<String, dynamic> json) => BusinessContact(
        businessName: (json['businessName'] ?? AppConfig.appName) as String,
        adminContactName: json['adminContactName'] as String?,
        adminPhone: json['adminPhone'] as String?,
        adminEmail: json['adminEmail'] as String?,
        supportPhone: json['supportPhone'] as String?,
        supportEmail: json['supportEmail'] as String?,
        whatsappNumber: json['whatsappNumber'] as String?,
        address: json['address'] as String?,
        websiteUrl: json['websiteUrl'] as String?,
        termsUrl: json['termsUrl'] as String?,
        privacyUrl: json['privacyUrl'] as String?,
        workingHours: json['workingHours'] as String?,
        supportHours: json['supportHours'] as String?,
      );

  /// Preferred number for a customer to call.
  String? get callNumber => supportPhone ?? adminPhone;

  /// Preferred address for a customer to email.
  String? get emailAddress => supportEmail ?? adminEmail;

  bool get hasPhone => (callNumber ?? '').isNotEmpty;
  bool get hasEmail => (emailAddress ?? '').isNotEmpty;
  bool get hasWhatsapp => (whatsappNumber ?? '').isNotEmpty;
  bool get hasTerms => (termsUrl ?? '').isNotEmpty;
  bool get hasPrivacy => (privacyUrl ?? '').isNotEmpty;
}
