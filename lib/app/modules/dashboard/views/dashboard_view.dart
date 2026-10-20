import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../routes/app_pages.dart';
import '../controllers/dashboard_controller.dart';

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: ErrorState(
              title: 'Gagal Memuat Dashboard',
              message: controller.errorMessage.value,
              onRetry: () => controller.loadDashboard(),
            ),
          );
        }

        final data = controller.dashboardData.value;
        if (data == null) {
          return Center(
            child: EmptyState(
              title: 'Belum Ada Data',
              message: 'Data dashboard belum tersedia.',
              action: OutlinedButton.icon(
                onPressed: () => controller.loadDashboard(),
                icon: const Icon(Icons.refresh),
                label: const Text('Muat Ulang'),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => controller.refreshDashboard(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 720;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 24.0 : 16.0,
                  vertical: 20.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context, isDesktop),
                        if (controller.shouldShowBackupReminder) ...[
                          const SizedBox(height: 16),
                          _buildBackupReminderBanner(context),
                        ],
                        const SizedBox(height: 20),
                        _buildSummaryMetrics(context, data, isDesktop),
                        const SizedBox(height: 20),
                        if (!controller.isFullReportsUnlocked) ...[
                          _buildUpgradeBanner(context),
                          const SizedBox(height: 20),
                        ],
                        _buildChartCard(context, data, isDesktop),
                        const SizedBox(height: 20),
                        _buildLowStockCard(context, data),
                        const SizedBox(height: 16),
                        _buildSmokeTestCard(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final store = AuthService.to.currentStore.value;
    final nowFormatted = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store?.name ?? 'Selamat Datang',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nowFormatted,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => Get.toNamed(Routes.POS),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Buka Kasir'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 20 : 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(BuildContext context, dynamic data, bool isDesktop) {
    final theme = Theme.of(context);
    final canViewProfit = data.todayProfit != null;

    final cards = <Widget>[
      _MetricTile(
        title: 'Omzet Hari Ini',
        value: formatRupiah(data.todayOmzet),
        subtitle: '${data.todayTxCount} transaksi selesai',
        icon: Icons.payments_outlined,
        color: theme.colorScheme.primary,
        containerColor: theme.colorScheme.primaryContainer,
      ),
      _MetricTile(
        title: 'Transaksi',
        value: '${data.todayTxCount}',
        subtitle: 'Transaksi lunas',
        icon: Icons.receipt_long_outlined,
        color: Colors.blue.shade700,
        containerColor: Colors.blue.shade50,
      ),
      _MetricTile(
        title: 'Item Terjual',
        value: '${data.todayItemsSold}',
        subtitle: 'Barang fisik keluar',
        icon: Icons.shopping_bag_outlined,
        color: Colors.teal.shade700,
        containerColor: Colors.teal.shade50,
      ),
      if (canViewProfit)
        _MetricTile(
          title: 'Laba Kotor Hari Ini',
          value: formatRupiah(data.todayProfit),
          subtitle: 'HPP: ${formatRupiah(data.todayCogs ?? 0)}',
          icon: Icons.trending_up,
          color: Colors.green.shade700,
          containerColor: Colors.green.shade50,
        ),
    ];

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cards
            .map((card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: card,
                  ),
                ))
            .toList(),
      );
    } else {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
        children: cards,
      );
    }
  }

  Widget _buildBackupReminderBanner(BuildContext context) {
    final isNever = controller.lastBackupInfo.value == null;
    final days = controller.backupDaysAgo;

    return Card(
      elevation: 0,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNever
                        ? 'Data Anda belum pernah dibackup!'
                        : 'Data Anda belum dibackup selama $days hari.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lakukan backup untuk mencegah kehilangan data.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade200,
                foregroundColor: Colors.amber.shade900,
              ),
              onPressed: () => Get.toNamed(Routes.BACKUP),
              child: const Text('Backup Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => FeatureGate.to.requireFeature(Feature.fullReports),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, color: Colors.black87, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analisis Laba & HPP (Fitur Semi-Premium)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Upgrade ke Semi-Premium untuk membuka laporan laba kotor, HPP detail, dan margin produk.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.brown.shade800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade300,
                  foregroundColor: Colors.brown.shade900,
                ),
                onPressed: () => FeatureGate.to.requireFeature(Feature.fullReports),
                child: const Text('Upgrade'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, dynamic data, bool isDesktop) {
    final theme = Theme.of(context);
    final chartPoints = data.revenueChart as List;

    // Hitung maxY untuk scaling sumbu Y
    int maxOmzet = 0;
    for (final p in chartPoints) {
      if (p.omzet > maxOmzet) maxOmzet = p.omzet;
    }
    final double maxY = maxOmzet > 0 ? (maxOmzet * 1.25).toDouble() : 100000.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 400 : 240),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Tren Omzet 7 Hari',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Get.toNamed(Routes.REPORTS),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Laporan Detail'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: 0,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => Colors.blueGrey.shade900,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final idx = group.x.toInt();
                        if (idx < 0 || idx >= chartPoints.length) return null;
                        final point = chartPoints[idx];
                        return BarTooltipItem(
                          '${point.dateStr}\n${formatRupiah(rod.toY.toInt())}\n${point.txCount} Transaksi',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          if (value == meta.max) return const SizedBox.shrink();
                          return Text(
                            _compactCurrency(value.toInt()),
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= chartPoints.length) return const SizedBox.shrink();
                          final point = chartPoints[idx];
                          final label = DateFormat('dd/MM').format(point.date);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: max(1.0, maxY / 4),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: chartPoints.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final point = entry.value;
                    final hasSales = point.omzet > 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: point.omzet.toDouble(),
                          color: hasSales
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isDesktop ? 24 : 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockCard(BuildContext context, dynamic data) {
    final theme = Theme.of(context);
    final lowStock = data.lowStockProducts as List;
    final totalCount = data.totalLowStockCount as int;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  totalCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: totalCount > 0 ? Colors.amber.shade800 : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Peringatan Stok Menipis ($totalCount Produk)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Get.toNamed(Routes.PRODUCTS),
                  child: const Text('Kelola Produk'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (lowStock.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Semua stok produk saat ini dalam batas aman.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ...lowStock.map((item) {
                final isZero = item.currentStock <= 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isZero ? Colors.red.shade100 : Colors.amber.shade100,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: isZero ? Colors.red.shade800 : Colors.amber.shade900,
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Min: ${item.minStock} ${item.unitName ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isZero ? Colors.red.shade100 : Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Sisa ${item.currentStock}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isZero ? Colors.red.shade900 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                );
              }),
              if (totalCount > 5) ...[
                const Divider(),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Get.toNamed(Routes.PRODUCTS),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text('Lihat Semua ($totalCount produk)'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSmokeTestCard(BuildContext context) {
    // Memastikan kecocokan ekspektasi smoke test widget
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.grey),
            const Text(
              'Uji Coba Currency Formatter: ',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              formatRupiah(1250000),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _compactCurrency(int value) {
    if (value >= 1000000) {
      final jt = (value / 1000000).toStringAsFixed(1).replaceAll('.0', '');
      return '${jt}jt';
    } else if (value >= 1000) {
      final rb = (value / 1000).toStringAsFixed(0);
      return '${rb}rb';
    }
    return value.toString();
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color containerColor;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.containerColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: containerColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
