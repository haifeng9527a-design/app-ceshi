class Article {
  Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.date,
  });

  final String id;
  final String title;
  final String summary;
  final String date;
}

class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.title,
    required this.date,
    required this.location,
  });

  final String id;
  final String title;
  final String date;
  final String location;
}

class StrategyItem {
  StrategyItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.date,
  });

  final String id;
  final String title;
  final String summary;
  final String date;
}

class TradeRecord {
  TradeRecord({
    required this.id,
    required this.asset,
    required this.buyTime,
    required this.buyShares,
    required this.buyPrice,
    required this.sellTime,
    required this.sellShares,
    required this.sellPrice,
    required this.pnlRatio,
    required this.pnlAmount,
  });

  final String id;
  final String asset;
  final String buyTime;
  final String buyShares;
  final String buyPrice;
  final String sellTime;
  final String sellShares;
  final String sellPrice;
  final double pnlRatio;
  final double pnlAmount;
}

class PositionRecord {
  PositionRecord({
    required this.id,
    required this.asset,
    required this.buyTime,
    required this.buyShares,
    required this.buyPrice,
    required this.costPrice,
    required this.currentPrice,
    required this.floatingPnl,
    required this.pnlRatio,
    required this.pnlAmount,
  });

  final String id;
  final String asset;
  final String buyTime;
  final String buyShares;
  final String buyPrice;
  final String costPrice;
  final String currentPrice;
  final double floatingPnl;
  final double pnlRatio;
  final double pnlAmount;
}

class Teacher {
  Teacher({
    required this.id,
    required this.name,
    required this.title,
    required this.avatarUrl,
    required this.bio,
    required this.tags,
    required this.wins,
    required this.losses,
    required this.rating,
    required this.todayStrategy,
    required this.strategyHistory,
    required this.trades,
    required this.positions,
    required this.historyPositions,
    required this.pnlCurrent,
    required this.pnlMonth,
    required this.pnlYear,
    required this.pnlTotal,
    required this.comments,
    required this.articles,
    required this.schedules,
  });

  final String id;
  final String name;
  final String title;
  final String avatarUrl;
  final String bio;
  final List<String> tags;
  final int wins;
  final int losses;
  final int rating;
  final String todayStrategy;
  final List<StrategyItem> strategyHistory;
  final List<TradeRecord> trades;
  final List<PositionRecord> positions;
  final List<PositionRecord> historyPositions;
  final double pnlCurrent;
  final double pnlMonth;
  final double pnlYear;
  final double pnlTotal;
  final List<Comment> comments;
  final List<Article> articles;
  final List<ScheduleItem> schedules;
}

class Comment {
  Comment({
    required this.id,
    required this.userName,
    required this.content,
    required this.date,
    this.replyToCommentId,
    this.replyToContent,
    this.avatarUrl,
  });

  final String id;
  final String userName;
  final String content;
  final String date;
  /// 被回复的评论 ID
  final String? replyToCommentId;
  /// 被回复评论的内容摘要
  final String? replyToContent;
  /// 评论者头像 URL
  final String? avatarUrl;
}

class RankingEntry {
  RankingEntry({
    required this.teacherId,
    required this.score,
  });

  final String teacherId;
  final int score;
}
