class TeacherProfile {
  const TeacherProfile({
    required this.userId,
    this.displayName,
    this.realName,
    this.title,
    this.organization,
    this.country,
    this.city,
    this.yearsExperience,
    this.markets,
    this.instruments,
    this.certifications,
    this.licenseNo,
    this.broker,
    this.trackRecord,
    this.applicationAck,
    this.idPhotoUrl,
    this.licensePhotoUrl,
    this.certificationPhotoUrl,
    this.bio,
    this.style,
    this.riskLevel,
    this.specialties,
    this.avatarUrl,
    this.status,
    this.frozenUntil,
    this.tags,
    this.wins,
    this.losses,
    this.rating,
    this.todayStrategy,
    this.pnlCurrent,
    this.pnlMonth,
    this.pnlYear,
    this.pnlTotal,
    this.signature,
  });

  final String userId;
  final String? displayName;
  final String? realName;
  final String? title;
  final String? signature;
  final String? organization;
  final String? country;
  final String? city;
  final int? yearsExperience;
  final String? markets;
  final String? instruments;
  final String? certifications;
  final String? licenseNo;
  final String? broker;
  final String? trackRecord;
  final bool? applicationAck;
  final String? idPhotoUrl;
  final String? licensePhotoUrl;
  final String? certificationPhotoUrl;
  final String? bio;
  final String? style;
  final String? riskLevel;
  final List<String>? specialties;
  final String? avatarUrl;
  final String? status;
  final DateTime? frozenUntil;
  final List<String>? tags;
  final int? wins;
  final int? losses;
  final int? rating;
  final String? todayStrategy;
  final num? pnlCurrent;
  final num? pnlMonth;
  final num? pnlYear;
  final num? pnlTotal;

  factory TeacherProfile.fromMap(Map<String, dynamic> row) {
    return TeacherProfile(
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String?,
      realName: row['real_name'] as String?,
      title: row['title'] as String?,
      organization: row['organization'] as String?,
      country: row['country'] as String?,
      city: row['city'] as String?,
      yearsExperience: row['years_experience'] as int?,
      markets: row['markets'] as String?,
      instruments: row['instruments'] as String?,
      certifications: row['certifications'] as String?,
      licenseNo: row['license_no'] as String?,
      broker: row['broker'] as String?,
      trackRecord: row['track_record'] as String?,
      applicationAck: row['application_ack'] as bool?,
      idPhotoUrl: row['id_photo_url'] as String?,
      licensePhotoUrl: row['license_photo_url'] as String?,
      certificationPhotoUrl: row['certification_photo_url'] as String?,
      bio: row['bio'] as String?,
      style: row['style'] as String?,
      riskLevel: row['risk_level'] as String?,
      specialties: (row['specialties'] as List?)
          ?.map((item) => item.toString())
          .toList(),
      avatarUrl: row['avatar_url'] as String?,
      status: row['status'] as String?,
      frozenUntil: row['frozen_until'] != null
          ? DateTime.tryParse(row['frozen_until'].toString())
          : null,
      tags: (row['tags'] as List?)?.map((item) => item.toString()).toList(),
      wins: row['wins'] as int?,
      losses: row['losses'] as int?,
      rating: row['rating'] as int?,
      todayStrategy: row['today_strategy'] as String?,
      pnlCurrent: row['pnl_current'] as num?,
      pnlMonth: row['pnl_month'] as num?,
      pnlYear: row['pnl_year'] as num?,
      pnlTotal: row['pnl_total'] as num?,
      signature: row['signature'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'real_name': realName,
      'title': title,
      'organization': organization,
      'country': country,
      'city': city,
      'years_experience': yearsExperience,
      'markets': markets,
      'instruments': instruments,
      'certifications': certifications,
      'license_no': licenseNo,
      'broker': broker,
      'track_record': trackRecord,
      'application_ack': applicationAck,
      'id_photo_url': idPhotoUrl,
      'license_photo_url': licensePhotoUrl,
      'certification_photo_url': certificationPhotoUrl,
      'bio': bio,
      'style': style,
      'risk_level': riskLevel,
      'specialties': specialties,
      'avatar_url': avatarUrl,
      'status': status,
      if (frozenUntil != null) 'frozen_until': frozenUntil!.toIso8601String(),
      'tags': tags,
      'wins': wins,
      'losses': losses,
      'rating': rating,
      'today_strategy': todayStrategy,
      'pnl_current': pnlCurrent,
      'pnl_month': pnlMonth,
      'pnl_year': pnlYear,
      'pnl_total': pnlTotal,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
