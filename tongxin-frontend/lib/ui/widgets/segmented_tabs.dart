import 'package:flutter/material.dart';

import '../tv_theme.dart';

/// TradingView 风格分段控件：胶囊底 + 滑块选中态，轻高亮
class SegmentedTabs extends StatefulWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<SegmentedTabs> createState() => _SegmentedTabsState();
}

class _SegmentedTabsState extends State<SegmentedTabs> {
  int _hoveredIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TvTheme.surface,
        borderRadius: BorderRadius.circular(TvTheme.radiusSm),
        border: Border.all(color: TvTheme.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.labels.length, (i) {
          final selected = i == widget.selectedIndex;
          final hover = i == _hoveredIndex;
          return Padding(
            padding: const EdgeInsets.only(left: 2, right: 2),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hoveredIndex = i),
              onExit: (_) => setState(() => _hoveredIndex = -1),
              cursor: SystemMouseCursors.click,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onSelected(i),
                  borderRadius: BorderRadius.circular(TvTheme.radiusSm - 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? TvTheme.positive.withValues(alpha: 0.15)
                          : (hover ? TvTheme.rowHoverBg : null),
                      borderRadius: BorderRadius.circular(TvTheme.radiusSm - 2),
                      border: selected
                          ? Border.all(color: TvTheme.positive.withValues(alpha: 0.4), width: 1)
                          : null,
                    ),
                    child: Text(
                      widget.labels[i],
                      style: TvTheme.bodySecondary.copyWith(
                        color: selected ? TvTheme.positive : TvTheme.textSecondary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
