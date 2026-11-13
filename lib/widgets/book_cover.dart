import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';

const List<List<Color>> kCoverAccents = [
  [Color(0xFF33514A), Color(0xFF6D9488)],
  [Color(0xFF5B463B), Color(0xFF9C7A5C)],
  [Color(0xFF3C4A66), Color(0xFF7687AB)],
  [Color(0xFF573845), Color(0xFF9A6478)],
  [Color(0xFF3D4A3C), Color(0xFF7A8F6E)],
  [Color(0xFF4A3B57), Color(0xFF8B77A0)],
];

/// 书架封面：EPUB 有封面图就用图（按显示尺寸解码，省内存），否则生成一张色卡。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.borderRadius = 10});

  final Book book;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = path == null ? null : File(path);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
            if (file != null && file.existsSync()) {
              return Image.file(
                file,
                fit: BoxFit.cover,
                // 按实际显示宽度解码，几十本书也不会把内存吃满
                cacheWidth: (width * dpr).round(),
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _generated(context),
              );
            }
            return _generated(context);
          },
        ),
      ),
    );
  }

  Widget _generated(BuildContext context) {
    final pair = kCoverAccents[book.accentIndex % kCoverAccents.length];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 100.0;
        final titleSize = (w * 0.13).clamp(10.0, 17.0);
        final authorSize = (w * 0.085).clamp(7.5, 10.0);
        final title = book.title.replaceAll(RegExp(r'《|》'), '');
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: pair,
            ),
          ),
          child: Stack(
            children: [
              // 左侧书脊高光，让色卡有点纸书的层次
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.14, w * 0.14, w * 0.1, w * 0.12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: w * 0.22,
                      height: 2,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    const Spacer(),
                    Text(
                      title.length > 22 ? '${title.substring(0, 22)}…' : title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        shadows: const [Shadow(color: Color(0x33000000), blurRadius: 4)],
                      ),
                    ),
                    if (book.author.isNotEmpty) ...[
                      SizedBox(height: w * 0.05),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: authorSize,
                        ),
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
