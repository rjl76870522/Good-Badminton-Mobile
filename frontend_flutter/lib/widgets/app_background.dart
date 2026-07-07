import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.imageAsset = 'assets/images/badminton_dashboard_bg.png',
    this.imageOpacity = 0.16,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final String imageAsset;
  final double imageOpacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF9FCF4),
                Color(0xFFF0F7EC),
                Color(0xFFE8F1E4),
              ],
            ),
          ),
        ),
        Image.asset(
          imageAsset,
          fit: BoxFit.cover,
          alignment: alignment,
          opacity: AlwaysStoppedAnimation(imageOpacity),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.75, -0.92),
              radius: 1.25,
              colors: [
                Color(0x66C8E6C9),
                Color(0x00C8E6C9),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
