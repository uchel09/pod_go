import 'package:flutter/material.dart';

class AdaptiveScaffoldDestination {
  final String label;
  final Widget icon;
  final Widget? selectedIcon;
  final String? route;
  final String? permission;

  const AdaptiveScaffoldDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.route,
    this.permission,
  });
}

class AdaptiveScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget body;
  final List<AdaptiveScaffoldDestination> destinations;
  final int currentIndex;
  final ValueChanged<int>? onDestinationSelected;
  final Widget? floatingActionButton;
  final Widget? railLeading;
  final Widget? railTrailing;
  final double breakpoint;

  const AdaptiveScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    required this.body,
    required this.destinations,
    this.currentIndex = 0,
    this.onDestinationSelected,
    this.floatingActionButton,
    this.railLeading,
    this.railTrailing,
    this.breakpoint = 600.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= breakpoint;

        if (isDesktop) {
          return _buildDesktopLayout(context);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (title == null && titleWidget == null && (actions == null || actions!.isEmpty)) {
      return null;
    }

    return AppBar(
      title: titleWidget ?? (title != null ? Text(title!) : null),
      actions: actions,
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          if (destinations.isNotEmpty) ...[
            NavigationRail(
              selectedIndex: currentIndex < destinations.length ? currentIndex : 0,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: railLeading,
              trailing: railTrailing != null
                  ? Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: railTrailing,
                        ),
                      ),
                    )
                  : null,
              destinations: destinations.map((dest) {
                return NavigationRailDestination(
                  icon: dest.icon,
                  selectedIcon: dest.selectedIcon ?? dest.icon,
                  label: Text(dest.label),
                );
              }).toList(),
            ),
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: colorScheme.outlineVariant,
            ),
          ],
          Expanded(
            child: Scaffold(
              appBar: _buildAppBar(context),
              body: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    // If more than 5 items, use Drawer; otherwise use NavigationBar
    final useDrawer = destinations.length > 5;

    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: useDrawer && destinations.isNotEmpty
          ? Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ?railLeading,
                        const SizedBox(height: 8),
                        Text(
                          title ?? 'Menu',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...destinations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final dest = entry.value;
                    final isSelected = index == currentIndex;

                    return ListTile(
                      leading: isSelected ? (dest.selectedIcon ?? dest.icon) : dest.icon,
                      title: Text(dest.label),
                      selected: isSelected,
                      onTap: () {
                        Navigator.of(context).pop(); // close drawer
                        onDestinationSelected?.call(index);
                      },
                    );
                  }),
                ],
              ),
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: (!useDrawer && destinations.isNotEmpty)
          ? NavigationBar(
              selectedIndex: currentIndex < destinations.length ? currentIndex : 0,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations.map((dest) {
                return NavigationDestination(
                  icon: dest.icon,
                  selectedIcon: dest.selectedIcon ?? dest.icon,
                  label: dest.label,
                );
              }).toList(),
            )
          : null,
    );
  }
}
