import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/notification_service.dart';
import '../../core/supabase_bootstrap.dart';
import '../home/featured_teacher_page.dart';
import '../messages/friends_repository.dart';
import '../messages/message_models.dart';
import '../messages/messages_page.dart';
import '../messages/messages_repository.dart';
import '../market/market_page.dart';
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

  final List<Widget> _pages = const [
    RankingsPage(),
    MarketPage(),
    FeaturedTeacherPage(),
    MessagesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeIncomingRequests();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      _subscribeIncomingRequests();
    });
  }

  @override
  void dispose() {
    _incomingRequestsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _subscribeIncomingRequests() {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    _incomingRequestsSubscription?.cancel();
    if (userId.isEmpty || !SupabaseBootstrap.isReady) {
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
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final canLoadMessages =
        userId.isNotEmpty && SupabaseBootstrap.isReady;
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: StreamBuilder<List<Conversation>>(
        stream: canLoadMessages
            ? _messagesRepo.watchConversations(userId: userId)
            : Stream.value(<Conversation>[]),
        builder: (context, snapshot) {
          final conversations = snapshot.data ?? const <Conversation>[];
          final chatUnread =
              conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
          final totalUnread = chatUnread + _pendingFriendRequestCount;
          // 一旦有数据就同步应用图标角标（含 0，避免角标不更新或不清零）
          if (snapshot.hasData) {
            NotificationService.updateBadgeCount(totalUnread);
          }
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '主页',
              ),
              const NavigationDestination(
                icon: Icon(Icons.show_chart_outlined),
                selectedIcon: Icon(Icons.show_chart),
                label: '行情',
              ),
              const NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events),
                label: '关注',
              ),
              NavigationDestination(
                icon: _wrapMessageIcon(context,
                    Icons.chat_bubble_outline, totalUnread),
                selectedIcon: _wrapMessageIcon(context,
                    Icons.chat_bubble, totalUnread),
                label: '消息',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          );
        },
      ),
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
          color: Colors.white,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.error,
      child: iconWidget,
    );
  }
}
