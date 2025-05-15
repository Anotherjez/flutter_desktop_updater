import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:desktop_updater/widget/update_card.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

class DesktopUpdateDirectCard extends StatefulWidget {
  const DesktopUpdateDirectCard({
    super.key,
    required this.controller,
    required this.child,
    this.releaseNotesLink,
    this.title,
    this.subtitle,
  });

  final DesktopUpdaterController controller;
  final Widget child;
  final String? releaseNotesLink;
  final Text? title;
  final Text? subtitle;

  @override
  State<DesktopUpdateDirectCard> createState() =>
      _DesktopUpdateDirectCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DesktopUpdaterController>(
        "controller",
        controller,
      ),
    );
  }
}

class _DesktopUpdateDirectCardState extends State<DesktopUpdateDirectCard> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopUpdaterInheritedNotifier(
      controller: widget.controller,
      child: StatefulBuilder(
        builder: (context, setState) {
          final desktopInheritedNotifier =
              DesktopUpdaterInheritedNotifier.of(context);
          final notifier = desktopInheritedNotifier?.notifier;

          if (((notifier?.needUpdate ?? false) == false) ||
              (notifier?.skipUpdate ?? false)) {
            // Empty sliver empty to avoid error
            return const SizedBox();
          } else {
            return UpdateCard(
              releaseNotesLink: widget.releaseNotesLink,
              title: widget.title,
              subtitle: widget.subtitle,
            );
          }
        },
      ),
    );
  }
}
