import 'package:flutter/material.dart';

import 'market_repository.dart';
import 'stock_chart_page.dart';

/// 涨跌榜：Gainers / Losers 两个 Tab，列表点击进 StockChartPage
class GainersLosersPage extends StatefulWidget {
  const GainersLosersPage({super.key});

  @override
  State<GainersLosersPage> createState() => _GainersLosersPageState();
}

class _GainersLosersPageState extends State<GainersLosersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  List<PolygonGainer> _gainers = [];
  List<PolygonGainer> _losers = [];
  bool _loadingGainers = true;
  bool _loadingLosers = true;
  String? _errorGainers;
  String? _errorLosers;

  static const _bg = Color(0xFF0B0C0E);
  static const _surface = Color(0xFF111215);
  static const _accent = Color(0xFFD4AF37);
  static const _muted = Color(0xFF9CA3AF);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGainers();
    _loadLosers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGainers() async {
    setState(() {
      _loadingGainers = true;
      _errorGainers = null;
    });
    try {
      final list = await _market.getTopGainers(limit: 50);
      if (!mounted) return;
      setState(() {
        _gainers = list;
        _loadingGainers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorGainers = e.toString();
        _loadingGainers = false;
      });
    }
  }

  Future<void> _loadLosers() async {
    setState(() {
      _loadingLosers = true;
      _errorLosers = null;
    });
    try {
      final list = await _market.getTopLosers(limit: 50);
      if (!mounted) return;
      setState(() {
        _losers = list;
        _loadingLosers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorLosers = e.toString();
        _loadingLosers = false;
      });
    }
  }

  void _openChart(PolygonGainer g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockChartPage(
          symbol: g.ticker,
          initialSnapshot: g,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          '涨跌榜',
          style: TextStyle(
            color: Color(0xFFE8D5A3),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFE8D5A3)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _accent,
          unselectedLabelColor: _muted,
          indicatorColor: _accent,
          tabs: const [
            Tab(text: 'Gainers'),
            Tab(text: 'Losers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(
            list: _gainers,
            loading: _loadingGainers,
            error: _errorGainers,
            isGainers: true,
            onRefresh: _loadGainers,
          ),
          _buildList(
            list: _losers,
            loading: _loadingLosers,
            error: _errorLosers,
            isGainers: false,
            onRefresh: _loadLosers,
          ),
        ],
      ),
    );
  }

  Widget _buildList({
    required List<PolygonGainer> list,
    required bool loading,
    required String? error,
    required bool isGainers,
    required Future<void> Function() onRefresh,
  }) {
    if (loading && list.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      );
    }
    if (error != null && list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Color(0xFF6B6B70)),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('重试'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            ],
          ),
        ),
      );
    }
    if (list.isEmpty) {
      return const Center(
        child: Text(
          '暂无数据',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (context, i) {
          final g = list[i];
          final price = g.price ?? 0.0;
          final change = g.todaysChange;
          final changePct = g.todaysChangePerc;
          final color = isGainers ? _green : _red;
          return Material(
            color: _surface,
            child: InkWell(
              onTap: () => _openChart(g),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.ticker,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      price > 0 ? price.toStringAsFixed(2) : '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                        style: TextStyle(color: color, fontSize: 13),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
