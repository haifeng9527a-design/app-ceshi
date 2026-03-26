import 'package:flutter/material.dart';

/// 策略预览图统一规格：
/// 1张 -> 单张大图（4:3）
/// 2张 -> 左右并排双图
/// 3张及以上 -> 左大图 + 右侧上下双图
class StrategyImagePreviewGrid extends StatelessWidget {
  const StrategyImagePreviewGrid({
    super.key,
    required this.imageUrls,
    required this.onImageTap,
    this.spacing = 6,
    this.borderRadius = 10,
    this.maxPreviewCount = 3,
  });

  final List<String> imageUrls;
  final ValueChanged<int> onImageTap;
  final double spacing;
  final double borderRadius;
  final int maxPreviewCount;

  @override
  Widget build(BuildContext context) {
    final cleanedUrls = imageUrls
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);
    final previewUrls = cleanedUrls
        .take(maxPreviewCount)
        .toList(growable: false);
    if (previewUrls.isEmpty) return const SizedBox.shrink();
    final extraCount = cleanedUrls.length - previewUrls.length;

    if (previewUrls.length == 1) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: _PreviewImageTile(
          url: previewUrls.first,
          borderRadius: borderRadius,
          onTap: () => onImageTap(0),
        ),
      );
    }

    if (previewUrls.length == 2) {
      return Row(
        children: List.generate(2, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 1 ? 0 : spacing),
              child: AspectRatio(
                aspectRatio: 1,
                child: _PreviewImageTile(
                  url: previewUrls[i],
                  borderRadius: borderRadius,
                  onTap: () => onImageTap(i),
                ),
              ),
            ),
          );
        }),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.only(right: spacing),
              child: _PreviewImageTile(
                url: previewUrls[0],
                borderRadius: borderRadius,
                onTap: () => onImageTap(0),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: spacing / 2),
                    child: _PreviewImageTile(
                      url: previewUrls[1],
                      borderRadius: borderRadius,
                      onTap: () => onImageTap(1),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: spacing / 2),
                    child: _PreviewImageTile(
                      url: previewUrls[2],
                      borderRadius: borderRadius,
                      onTap: () => onImageTap(2),
                      overlayText: extraCount > 0 ? '+$extraCount' : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImageTile extends StatelessWidget {
  const _PreviewImageTile({
    required this.url,
    required this.borderRadius,
    required this.onTap,
    this.overlayText,
  });

  final String url;
  final double borderRadius;
  final VoidCallback onTap;
  final String? overlayText;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SizedBox.expand(
              child: Image.network(
                url,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF111215),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white24,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (overlayText != null)
              Container(
                color: Colors.black.withValues(alpha: 0.38),
                alignment: Alignment.center,
                child: Text(
                  overlayText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
