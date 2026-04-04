DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

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
    this.pnlWeek,
    this.pnlMonth,
    this.pnlQuarter,
    this.pnlYear,
    this.pnlTotal,
    this.signature,
  });

  final String userId;
  final String? displayName;
  final String? realName;
  final String? title;
  /// 个性签名（与「我的」页同步，来自 user_profiles.signature）
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
  final num? pnlWeek;
  final num? pnlMonth;
  final num? pnlQuarter;
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
      pnlWeek: row['pnl_week'] as num?,
      pnlMonth: row['pnl_month'] as num?,
      pnlQuarter: row['pnl_quarter'] as num?,
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
      'pnl_week': pnlWeek,
      'pnl_month': pnlMonth,
      'pnl_quarter': pnlQuarter,
      'pnl_year': pnlYear,
      'pnl_total': pnlTotal,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class TeacherPnlMetrics {
  const TeacherPnlMetrics({
    required this.userId,
    required this.floatingPnl,
    required this.weekRealizedPnl,
    required this.monthRealizedPnl,
    required this.quarterRealizedPnl,
    required this.yearRealizedPnl,
    required this.totalRealizedPnl,
    required this.wins,
    required this.losses,
  });

  final String userId;
  final double floatingPnl;
  final double weekRealizedPnl;
  final double monthRealizedPnl;
  final double quarterRealizedPnl;
  final double yearRealizedPnl;
  final double totalRealizedPnl;
  final int wins;
  final int losses;

  factory TeacherPnlMetrics.fromMap(Map<String, dynamic> row) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return TeacherPnlMetrics(
      userId: row['user_id']?.toString() ?? '',
      floatingPnl: asDouble(row['floating_pnl'] ?? row['pnl_current']),
      weekRealizedPnl: asDouble(row['week_realized_pnl'] ?? row['pnl_week']),
      monthRealizedPnl:
          asDouble(row['month_realized_pnl'] ?? row['pnl_month']),
      quarterRealizedPnl:
          asDouble(row['quarter_realized_pnl'] ?? row['pnl_quarter']),
      yearRealizedPnl: asDouble(row['year_realized_pnl'] ?? row['pnl_year']),
      totalRealizedPnl:
          asDouble(row['total_realized_pnl'] ?? row['pnl_total']),
      wins: asInt(row['wins']),
      losses: asInt(row['losses']),
    );
  }

  factory TeacherPnlMetrics.fromProfile(TeacherProfile profile) {
    return TeacherPnlMetrics(
      userId: profile.userId,
      floatingPnl: (profile.pnlCurrent ?? 0).toDouble(),
      weekRealizedPnl: (profile.pnlWeek ?? 0).toDouble(),
      monthRealizedPnl: (profile.pnlMonth ?? 0).toDouble(),
      quarterRealizedPnl: (profile.pnlQuarter ?? 0).toDouble(),
      yearRealizedPnl: (profile.pnlYear ?? 0).toDouble(),
      totalRealizedPnl: (profile.pnlTotal ?? 0).toDouble(),
      wins: profile.wins ?? 0,
      losses: profile.losses ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'floating_pnl': floatingPnl,
      'week_realized_pnl': weekRealizedPnl,
      'month_realized_pnl': monthRealizedPnl,
      'quarter_realized_pnl': quarterRealizedPnl,
      'year_realized_pnl': yearRealizedPnl,
      'total_realized_pnl': totalRealizedPnl,
      'wins': wins,
      'losses': losses,
    };
  }
}

class TeacherStrategy {
  const TeacherStrategy({
    required this.id,
    required this.teacherId,
    required this.title,
    required this.summary,
    required this.status,
    required this.createdAt,
    this.content,
    this.imageUrls,
  });

  final String id;
  final String teacherId;
  final String title;
  final String summary;
  final String status;
  final DateTime createdAt;
  /// 策略正文（发布时填写的「策略内容」）
  final String? content;
  /// 策略配图 URL 列表
  final List<String>? imageUrls;

  factory TeacherStrategy.fromMap(Map<String, dynamic> row) {
    final urls = row['image_urls'];
    List<String>? list;
    if (urls is List) {
      list = urls.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else if (urls is String && urls.trim().isNotEmpty) {
      final raw = urls.trim();
      if (raw.startsWith('[') && raw.endsWith(']')) {
        // JSON 数组字符串
        final body = raw.substring(1, raw.length - 1).trim();
        if (body.isNotEmpty) {
          list = body
              .split(',')
              .map((e) => e.replaceAll('"', '').replaceAll("'", '').trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } else if (raw.startsWith('{') && raw.endsWith('}')) {
        // Postgres text[] 字面量
        final body = raw.substring(1, raw.length - 1).trim();
        if (body.isNotEmpty) {
          list = body
              .split(',')
              .map((e) => e.replaceAll('"', '').replaceAll("'", '').trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } else {
        list = raw
            .split(',')
            .map((e) => e.replaceAll('"', '').replaceAll("'", '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    final legacySingle = row['image_url']?.toString().trim();
    if ((list == null || list.isEmpty) && legacySingle != null && legacySingle.isNotEmpty) {
      list = [legacySingle];
    }
    if (list != null && list.isEmpty) list = null;
    return TeacherStrategy(
      id: row['id'] as String,
      teacherId: row['teacher_id'] as String,
      title: row['title'] as String? ?? '',
      summary: row['summary'] as String? ?? '',
      status: row['status'] as String? ?? 'draft',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      content: row['content'] as String?,
      imageUrls: list,
    );
  }
}

class TradeRecord {
  const TradeRecord({
    required this.id,
    required this.teacherId,
    required this.symbol,
    required this.side,
    required this.pnl,
    required this.tradeTime,
    required this.attachmentUrl,
    this.buyTime,
    this.buyPrice,
    this.buyShares,
    this.sellTime,
    this.sellPrice,
    this.sellShares,
    this.pnlAmount,
  });

  final String id;
  final String teacherId;
  final String symbol;
  final String side;
  final num pnl;
  final DateTime? tradeTime;
  final String? attachmentUrl;
  /// 买入时间（扩展列）
  final DateTime? buyTime;
  final double? buyPrice;
  final double? buyShares;
  final DateTime? sellTime;
  final double? sellPrice;
  final double? sellShares;
  final double? pnlAmount;

  factory TradeRecord.fromMap(Map<String, dynamic> row) {
    return TradeRecord(
      id: row['id'] as String,
      teacherId: row['teacher_id'] as String,
      symbol: row['symbol'] as String? ?? row['asset'] as String? ?? '',
      side: row['side'] as String? ?? '',
      pnl: row['pnl'] as num? ?? 0,
      tradeTime: _parseDateTime(row['trade_time']),
      attachmentUrl: row['attachment_url'] as String?,
      buyTime: _parseDateTime(row['buy_time']),
      buyPrice: (row['buy_price'] as num?)?.toDouble(),
      buyShares: (row['buy_shares'] as num?)?.toDouble(),
      sellTime: _parseDateTime(row['sell_time']),
      sellPrice: (row['sell_price'] as num?)?.toDouble(),
      sellShares: (row['sell_shares'] as num?)?.toDouble(),
      pnlAmount: (row['pnl_amount'] as num?)?.toDouble(),
    );
  }
}

/// 持仓（teacher_positions）
class TeacherPosition {
  const TeacherPosition({
    required this.id,
    required this.teacherId,
    required this.asset,
    this.assetClass,
    this.productType,
    this.positionSide,
    this.positionAction,
    this.marginMode,
    this.leverage,
    this.contractSize,
    this.multiplier,
    this.settlementAsset,
    this.buyTime,
    this.buyShares,
    this.buyPrice,
    this.costPrice,
    this.currentPrice,
    this.markPrice,
    this.indexPrice,
    this.liquidationPrice,
    this.usedMargin,
    this.maintenanceMargin,
    this.floatingPnl,
    this.pnlRatio,
    this.pnlAmount,
    this.sellTime,
    this.sellPrice,
    this.isHistory = false,
  });

  final String id;
  final String teacherId;
  final String asset;
  final String? assetClass;
  final String? productType;
  final String? positionSide;
  final String? positionAction;
  final String? marginMode;
  final double? leverage;
  final double? contractSize;
  final double? multiplier;
  final String? settlementAsset;
  final DateTime? buyTime;
  final double? buyShares;
  final double? buyPrice;
  final double? costPrice;
  final double? currentPrice;
  final double? markPrice;
  final double? indexPrice;
  final double? liquidationPrice;
  final double? usedMargin;
  final double? maintenanceMargin;
  final double? floatingPnl;
  final double? pnlRatio;
  final double? pnlAmount;
  /// 卖出时间（历史持仓）
  final DateTime? sellTime;
  /// 卖出价格（历史持仓，用于计算已实现盈亏与比例）
  final double? sellPrice;
  final bool isHistory;

  /// 历史持仓已实现盈亏金额（有 pnl_amount 或用 卖出价与成本推算）
  double? get realizedPnlAmount {
    if (pnlAmount != null) return pnlAmount;
    if (sellPrice != null && costPrice != null && costPrice! > 0 && buyShares != null) {
      return (sellPrice! - costPrice!) * buyShares!;
    }
    return null;
  }

  /// 历史持仓已实现盈亏比例%（有 pnl_ratio 或用 卖出价与成本推算）
  double? get realizedPnlRatioPercent {
    if (pnlRatio != null) return pnlRatio;
    if (sellPrice != null && costPrice != null && costPrice! > 0) {
      return ((sellPrice! - costPrice!) / costPrice!) * 100;
    }
    return null;
  }

  factory TeacherPosition.fromMap(Map<String, dynamic> row) {
    return TeacherPosition(
      id: row['id'] as String,
      teacherId: row['teacher_id'] as String,
      asset: row['asset'] as String? ?? '',
      assetClass: row['asset_class']?.toString(),
      productType: row['product_type']?.toString(),
      positionSide: row['position_side']?.toString(),
      positionAction: row['position_action']?.toString(),
      marginMode: row['margin_mode']?.toString(),
      leverage: (row['leverage'] as num?)?.toDouble(),
      contractSize: (row['contract_size'] as num?)?.toDouble(),
      multiplier: (row['multiplier'] as num?)?.toDouble(),
      settlementAsset: row['settlement_asset']?.toString(),
      buyTime: _parseDateTime(row['buy_time']),
      buyShares: (row['buy_shares'] as num?)?.toDouble(),
      buyPrice: (row['buy_price'] as num?)?.toDouble(),
      costPrice: (row['cost_price'] as num?)?.toDouble(),
      currentPrice: (row['current_price'] as num?)?.toDouble(),
      markPrice: (row['mark_price'] as num?)?.toDouble(),
      indexPrice: (row['index_price'] as num?)?.toDouble(),
      liquidationPrice: (row['liquidation_price'] as num?)?.toDouble(),
      usedMargin: (row['used_margin'] as num?)?.toDouble(),
      maintenanceMargin: (row['maintenance_margin'] as num?)?.toDouble(),
      floatingPnl: (row['floating_pnl'] as num?)?.toDouble(),
      pnlRatio: (row['pnl_ratio'] as num?)?.toDouble(),
      pnlAmount: (row['pnl_amount'] as num?)?.toDouble(),
      sellTime: _parseDateTime(row['sell_time']),
      sellPrice: (row['sell_price'] as num?)?.toDouble(),
      isHistory: row['is_history'] as bool? ?? false,
    );
  }
}
