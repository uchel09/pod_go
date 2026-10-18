import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../permissions/permission_service.dart';

/// Widget helper untuk merender UI hanya jika user memiliki hak akses [permission].
class PermissionGuard extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final allowed = PermissionService.to.can(permission);
      if (allowed) return child;
      return fallback ?? const SizedBox.shrink();
    });
  }
}

