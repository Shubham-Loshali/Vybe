import 'package:material_ui/material_ui.dart';
import 'package:vybe/widgets/marquee.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.primaryColor, {super.key, this.icon});
  final Color primaryColor;
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: MarqueeWidget(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
