import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../core/firebase_bootstrap.dart';
import '../../l10n/app_localizations.dart';
import '../../core/notification_service.dart';
import '../../core/pc_dashboard_page.dart';
import '../../core/pc_shell.dart';
import '../../core/api_client.dart';
import '../home/featured_teacher_page.dart';
import '../messages/friends_repository.dart';
import '../messages/message_models.dart';
import '../messages/messages_page.dart';
import '../messages/messages_repository.dart';
import '../market/market_page.dart';
import '../market/watchlist_page.dart';
import '../profile/profile_page.dart';
import '../rankings/rankings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final _messagesRepo = MessagesRepository();
  final _friendsRepo = FriendsRepository();
  int _pendingFriendRequestCount = 0;
  StreamSubscription? _incomingRequestsSubscription;
  StreamSubscription? _authSubscription;
  final GlobalKey<NavigatorState> _desktopContentNavKey = GlobalKey<NavigatorState>();

  static const double _kDesktopBreakpoint = 1100;

  final List<Widget> _pages = const [
    RankingsPage(),
    MarketPage(),
    FeaturedTeacherPage(),
    MessagesPage(),
    ProfilePage(),
  ];

  /// Desktop sidebar: Dashboard, Markets, Watchlist, Messages, Leaderboard, Profile
  final List<Widget> _desktopPages = const [
    PcDashboardPage(),
    MarketPage(),
    WatchlistPage(),
    MessagesPage(),
    RankingsPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeIncomingRequests();
    if (FirebaseBootstrap.isReady) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        _subscribeIncomingRequests();
      });
    }
  }

  @override
  void dispose() {
    _incomingRequestsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  Widget _desktopChildForIndex(int index) {
    final i = index.clamp(0, _desktopPages.length - 1);
    if (i == 0) {
      return PcDashboardPage(
        onNavigateToSection: (idx) => setState(() => _currentIndex = idx),
      );
    }
    return _desktopPages[i];
  }

  void _subscribeIncomingRequests() {
    if (!FirebaseBootstrap.isReady) {
      if (mounted) setState(() => _pendingFriendRequestCount = 0);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    _incomingRequestsSubscription?.cancel();
    if (userId.isEmpty || !ApiClient.instance.isAvailable) {
      if (mounted) setState(() => _pendingFriendRequestCount = 0);
      return;
    }
    _incomingRequestsSubscription = _friendsRepo
        .watchIncomingRequests(userId: userId)
        .listen((requests) {
      if (!mounted) return;
      setState(() {
        _pendingFriendRequestCount = requests.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseBootstrap.isReady
        ? (FirebaseAuth.instance.currentUser?.uid ?? '')
        : '';
    final canLoadMessages =
        userId.isNotEmpty && ApiClient.instance.isAvailable;
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = width >= _kDesktopBreakpoint;

    return StreamBuilder<List<Conversation>>(
      stream: canLoadMessages
          ? _messagesRepo.watchConversations(userId: userId)
          : Stream.value(<Conversation>[]),
      builder: (context, snapshot) {
        final conversations = snapshot.data ?? const <Conversation>[];
        final chatUnread =
            conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
        final totalUnread = chatUnread + _pendingFriendRequestCount;
        if (snapshot.hasData) {
          NotificationService.updateBadgeCount(totalUnread);
        }

        if (useDesktopLayout) {
          final desktopIndex = _currentIndex.clamp(0, _desktopPages.length - 1);
          return PcShell(
            currentIndex: desktopIndex,
            onDestinationSelected: (index) {
              final nav = _desktopContentNavKey.currentState;
              nav?.popUntil((route) => route.isFirst);
              nav?.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => _desktopChildForIndex(index),
                ),
              );
              setState(() => _currentIndex = index);
            },
            unreadCount: totalUnread,
            userAvatarUrl: FirebaseBootstrap.isReady
                ? FirebaseAuth.instance.currentUser?.photoURL
                : null,
            contentPadding: desktopIndex == 1 ? EdgeInsets.zero : null,
            child: Navigator(
              key: _desktopContentNavKey,
              initialRoute: '/',
              onGenerateRoute: (settings) {
                final name = settings.name ?? '/';
                if (name == '/') {
                  return MaterialPageRoute<void>(
                    builder: (_) => _desktopChildForIndex(desktopIndex),
                  );
                }
                return null;
              },
            ),
          );
        }

        final mobileIndex = _currentIndex == 5
            ? 4
            : (_currentIndex == 4
                ? 0
                : _currentIndex.clamp(0, 3));
        return Scaffold(
          body: _pages[mobileIndex],
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: NavigationBar(
              selectedIndex: mobileIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index == 4 ? 5 : index);
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(AppIcons.navHome),
                  selectedIcon: const Icon(AppIcons.navHomeActive),
                  label: AppLocalizations.of(context)!.navMainPage,
                ),
                NavigationDestination(
                  icon: const Icon(AppIcons.navMarket),
                  selectedIcon: const Icon(AppIcons.navMarketActive),
                  label: AppLocalizations.of(context)!.navMarket,
                ),
                NavigationDestination(
                  icon: const Icon(AppIcons.navFollow),
                  selectedIcon: const Icon(AppIcons.navFollowActive),
                  label: AppLocalizations.of(context)!.navFollow,
                ),
                NavigationDestination(
                  icon: _wrapMessageIcon(context, AppIcons.navMessages, totalUnread),
                  selectedIcon: _wrapMessageIcon(
                    context,
                    AppIcons.navMessagesActive,
                    totalUnread,
                  ),
                  label: AppLocalizations.of(context)!.navMessages,
                ),
                NavigationDestination(
                  icon: const Icon(AppIcons.navProfile),
                  selectedIcon: const Icon(AppIcons.navProfileActive),
                  label: AppLocalizations.of(context)!.navProfile,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _wrapMessageIcon(
      BuildContext context, IconData icon, int totalUnread) {
    final iconWidget = Icon(icon);
    if (totalUnread <= 0) {
      return iconWidget;
    }
    return Badge(
      label: Text(
        totalUnread > 99 ? '99+' : '$totalUnread',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.error,
      child: iconWidget,
    );
  }
}
