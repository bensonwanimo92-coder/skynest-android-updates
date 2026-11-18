import 'package:flutter/material.dart';

/// A subtle conveyor-belt ticker for the dashboard module cards.
class TileMarqueeText extends StatefulWidget {
  const TileMarqueeText({super.key, required this.text, this.color = Colors.white});
  final String text;
  final Color color;

  @override
  State<TileMarqueeText> createState() => _TileMarqueeTextState();
}

class _TileMarqueeTextState extends State<TileMarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final style = TextStyle(
          color: widget.color.withOpacity(.82),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textWidth = painter.width + 34;
        final viewport = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final travel = textWidth + viewport;
            final x = viewport - (_controller.value * travel);
            return SizedBox(
              width: viewport,
              height: 20,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: x,
                    top: 2,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.text, style: style),
                      const SizedBox(width: 34),
                      Text(widget.text, style: style),
                    ]),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
