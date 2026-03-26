import 'package:flutter/material.dart';

/// 统一图标语义层：业务代码尽量引用这里，避免各页随意挑图标导致风格割裂。
abstract class AppIcons {
  AppIcons._();

  // Bottom navigation
  static const IconData navHome = Icons.home_outlined;
  static const IconData navHomeActive = Icons.home_rounded;
  static const IconData navMarket = Icons.show_chart_outlined;
  static const IconData navMarketActive = Icons.show_chart_rounded;
  static const IconData navFollow = Icons.workspace_premium_outlined;
  static const IconData navFollowActive = Icons.workspace_premium_rounded;
  static const IconData navMessages = Icons.forum_outlined;
  static const IconData navMessagesActive = Icons.forum_rounded;
  static const IconData navProfile = Icons.account_circle_outlined;
  static const IconData navProfileActive = Icons.account_circle_rounded;

  // Common actions
  static const IconData addFriend = Icons.person_add_alt_1_rounded;
  static const IconData createGroup = Icons.group_add_rounded;
  static const IconData notifications = Icons.notifications_none_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData back = Icons.arrow_back_ios_new_rounded;
  static const IconData retry = Icons.refresh_rounded;

  // States
  static const IconData empty = Icons.inbox_outlined;
  static const IconData cloudOff = Icons.cloud_off_rounded;
}

