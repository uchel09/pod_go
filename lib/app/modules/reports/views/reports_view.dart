import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../core/features/feature_enum.dart';
import '../../../core/services/feature_gate.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../data/repositories/report_repository.dart';
import '../controllers/reports_controller.dart';

class ReportsView extends GetView<ReportsController> {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan Penjualan'),
          actions: [
            Obx(() {
              final isLocked = !controller.isFullReportsUnlocked;
              return TextButton.icon(
                onPressed: () => controller.handleExport(),
                icon: Icon(
                  isLocked ? Icons.lock_outline : Icons.file_download_outlined,
                  size: 20,
                  color: isLocked ? Colors.amber.shade800 : theme.colorScheme.primary,
                ),
                label: Text(
                  'Ekspor',
                  style: TextStyle(
                    color: isLocked ? Colors.amber.shade800 : theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
            IconButton(
              tooltip: 'Segarkan Laporan',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                controller.loadReports();
                if (controller.isFullReportsUnlocked) {
                  controller.loadFullReport();
                }
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(
                icon: Icon(Icons.calendar_month_outlined),
                text: 'Laporan Dasar (30 Hari)',
              ),
              Tab(
                child: Obx(() {
                  final isLocked = !controller.isFullReportsUnlocked;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.analytics_outlined),
                      const SizedBox(width: 6),
                      const Text('Laporan Lengkap'),
                      const SizedBox(width: 4),
                      if (isLocked)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBasicReportsTab(context),
            _buildFullReportsTab(context),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: LAPORAN PENJUALAN DASAR (30 HARI)
  // =========================================================================

  Widget _buildBasicReportsTab(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.errorMessage.isNotEmpty) {
        return Center(
          child: ErrorState(
            title: 'Gagal Memuat Laporan',
            message: controller.errorMessage.value,
            onRetry: () => controller.loadReports(),
          ),
        );
      }

      final reports = controller.reports;
      if (reports.isEmpty) {
        return Center(
          child: EmptyState(
            title: 'Belum Ada Transaksi',
            message: 'Tidak ada rekap penjualan dalam 30 hari terakhir.',
            icon: Icons.bar_chart_outlined,
            action: OutlinedButton.icon(
              onPressed: () => controller.loadReports(),
              icon: const Icon(Icons.refresh),
              label: const Text('Muat Ulang'),
            ),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () => controller.loadReports(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 720;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 24.0 : 16.0,
                    vertical: 16.0,
                  ),
                  children: [
                    _buildHeaderBanner(context),
                    const SizedBox(height: 16),
                    _buildSummaryCards(context, isDesktop),
                    const SizedBox(height: 16),
                    if (!controller.isFullReportsUnlocked) ...[
                      _buildLockedFullReportsBanner(context),
                      const SizedBox(height: 16),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Rekap Harian (30 Hari Terakhir)',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Ketuk baris untuk detail',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: reports.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = reports[index];
                            final formattedDate =
                                DateFormat('EEEE, dd MMMM yyyy').format(item.date);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 6.0,
                              ),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                              title: Text(
                                formattedDate,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${item.txCount} transaksi',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatRupiah(item.omzet),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, size: 20),
                                ],
                              ),
                              onTap: () => controller.openDailySalesHistory(item),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildHeaderBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Laporan ini merangkum omzet dari transaksi selesai (completed). Transaksi dibatalkan (void) tidak dihitung.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final totalOmzet = controller.totalRevenue30Days;
    final totalTx = controller.totalTx30Days;
    final count = controller.reports.length;
    final avgPerDay = count > 0 ? (totalOmzet / count).round() : 0;

    final widgets = [
      _SummaryCard(
        label: 'Total Omzet (30 Hari)',
        value: formatRupiah(totalOmzet),
        icon: Icons.payments_outlined,
        color: theme.colorScheme.primary,
      ),
      _SummaryCard(
        label: 'Total Transaksi Selesai',
        value: '$totalTx',
        icon: Icons.receipt_long_outlined,
        color: Colors.blue.shade700,
      ),
      _SummaryCard(
        label: 'Rata-rata Omzet / Hari',
        value: formatRupiah(avgPerDay),
        icon: Icons.show_chart,
        color: Colors.teal.shade700,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: widgets
            .map((w) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: w,
                  ),
                ))
            .toList(),
      );
    } else {
      return Column(
        children: widgets
            .map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: w,
                ))
            .toList(),
      );
    }
  }

  Widget _buildLockedFullReportsBanner(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.shade200,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock, color: Colors.black87, size: 20),
        ),
        title: const Text(
          'Laporan Laba & Analisis Lanjutan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Tersedia pada tier Semi-Premium (analisis laba kotor, HPP, margin produk, per kategori & kasir).',
        ),
        trailing: FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade300,
            foregroundColor: Colors.brown.shade900,
          ),
          onPressed: () => FeatureGate.to.requireFeature(Feature.fullReports),
          child: const Text('Upgrade'),
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 2: LAPORAN LENGKAP (SEMI-PREMIUM KE ATAS)
  // =========================================================================

  Widget _buildFullReportsTab(BuildContext context) {
    return Obx(() {
      // 1. Jika Tier lisensi belum Semi-Premium (FeatureGate fullReports belum aktif)
      if (!controller.isFullReportsUnlocked) {
        return _buildFullReportsUpgradeScreen(context);
      }

      // 2. Loading state
      if (controller.isLoadingFullReport.value) {
        return const Center(child: CircularProgressIndicator());
      }

      // 3. Error state
      if (controller.fullReportError.isNotEmpty) {
        return Center(
          child: ErrorState(
            title: 'Gagal Memuat Laporan Lengkap',
            message: controller.fullReportError.value,
            onRetry: () => controller.loadFullReport(),
          ),
        );
      }

      final report = controller.fullReport.value;
      if (report == null) {
        return Center(
          child: EmptyState(
            title: 'Laporan Belum Dimuat',
            message: 'Pilih rentang tanggal untuk menganalisis data penjualan.',
            icon: Icons.query_stats_outlined,
            action: FilledButton(
              onPressed: () => controller.loadFullReport(),
              child: const Text('Muat Laporan'),
            ),
          ),
        );
      }

      // 4. Render Laporan Lengkap
      return RefreshIndicator(
        onRefresh: () => controller.loadFullReport(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 840;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 24.0 : 16.0,
                    vertical: 16.0,
                  ),
                  children: [
                    _buildDatePresetSelector(context),
                    const SizedBox(height: 16),
                    _buildFullReportSummaryCards(context, report, isDesktop),
                    const SizedBox(height: 20),
                    _buildTopProductsSection(context, report),
                    const SizedBox(height: 20),
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildCategorySalesCard(context, report)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildPaymentMethodCard(context, report)),
                        ],
                      )
                    else ...[
                      _buildCategorySalesCard(context, report),
                      const SizedBox(height: 16),
                      _buildPaymentMethodCard(context, report),
                    ],
                    const SizedBox(height: 20),
                    if (!controller.isSoloMode && report.cashierSales != null) ...[
                      _buildCashierSalesCard(context, report),
                      const SizedBox(height: 20),
                    ],
                    _buildHourlySalesCard(context, report),
                    const SizedBox(height: 20),
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildStockValuationCard(context, report)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildStockAlertsCard(context, report)),
                        ],
                      )
                    else ...[
                      _buildStockValuationCard(context, report),
                      const SizedBox(height: 16),
                      _buildStockAlertsCard(context, report),
                    ],
                    const SizedBox(height: 20),
                    _buildVoidSummaryCard(context, report),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  /// Tampilan Upgrade jika tier lisensi belum memenuhi Semi-Premium
  Widget _buildFullReportsUpgradeScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.amber.shade300, width: 1.5),
            ),
            color: Colors.amber.shade50.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.workspace_premium, size: 54, color: Colors.amber.shade900),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Laporan Lengkap & Analisis Laba',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.brown.shade900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Buka wawasan bisnis mendalam UMKM Anda dengan fitur analisis Semi-Premium:',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.brown.shade700),
                  ),
                  const SizedBox(height: 20),
                  _buildUpgradeFeatureItem(Icons.date_range, 'Filter rentang tanggal bebas (Hari ini, 7 hari, Bulan lalu, Kustom)'),
                  _buildUpgradeFeatureItem(Icons.monetization_on_outlined, 'Laba kotor & HPP otomatis per transaksi dan produk'),
                  _buildUpgradeFeatureItem(Icons.leaderboard_outlined, 'Produk terlaris berdasarkan qty dan omzet'),
                  _buildUpgradeFeatureItem(Icons.pie_chart_outline, 'Rekap penjualan per kategori & per metode pembayaran'),
                  _buildUpgradeFeatureItem(Icons.people_outline, 'Kinerja per kasir (khusus Mode Tim) & jam ramai toko'),
                  _buildUpgradeFeatureItem(Icons.inventory_2_outlined, 'Valuasi nilai modal stok dan peringatan stok kritis'),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => FeatureGate.to.requireFeature(Feature.fullReports),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Upgrade ke Semi-Premium Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeFeatureItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// Selector Preset Rentang Tanggal
  Widget _buildDatePresetSelector(BuildContext context) {
    final theme = Theme.of(context);
    final currentPreset = controller.selectedPreset.value;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ReportDatePreset.values.map((preset) {
                  final isSelected = currentPreset == preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(preset.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          if (preset == ReportDatePreset.custom) {
                            _pickCustomDateRange(context);
                          } else {
                            controller.setPreset(preset);
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            if (currentPreset == ReportDatePreset.custom && controller.customDateRange.value != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_month, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Rentang: ${DateFormat('dd MMM yyyy').format(controller.customDateRange.value!.start)} - ${DateFormat('dd MMM yyyy').format(controller.customDateRange.value!.end)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _pickCustomDateRange(context),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('Ubah Tanggal', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: controller.customDateRange.value ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      helpText: 'Pilih Rentang Tanggal Laporan',
      cancelText: 'Batal',
      confirmText: 'Terapkan',
    );

    if (picked != null) {
      controller.setCustomRange(picked);
    }
  }

  /// Ringkasan KPI Utama (Omzet, Transaksi, Rata-rata/Tx, HPP & Laba)
  Widget _buildFullReportSummaryCards(
    BuildContext context,
    FullReportData report,
    bool isDesktop,
  ) {
    final theme = Theme.of(context);
    final canProfit = report.isProfitVisible;

    final cards = [
      _SummaryCard(
        label: 'Total Omzet (Penjualan)',
        value: formatRupiah(report.summary.omzet),
        icon: Icons.payments_outlined,
        color: theme.colorScheme.primary,
      ),
      _SummaryCard(
        label: 'Transaksi Selesai',
        value: '${report.summary.txCount} tx',
        icon: Icons.receipt_long_outlined,
        color: Colors.blue.shade700,
      ),
      _SummaryCard(
        label: 'Rata-rata / Transaksi',
        value: formatRupiah(report.avgTxValue),
        icon: Icons.show_chart,
        color: Colors.indigo.shade600,
      ),
      _SummaryCard(
        label: 'Total Barang Terjual',
        value: '${report.summary.itemsSold} item',
        icon: Icons.shopping_bag_outlined,
        color: Colors.teal.shade700,
      ),
      if (canProfit) ...[
        _SummaryCard(
          label: 'Total HPP (Modal Terjual)',
          value: formatRupiah(report.summary.cogs ?? 0),
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.orange.shade800,
        ),
        _SummaryCard(
          label: 'Laba Kotor',
          value: formatRupiah(report.summary.grossProfit ?? 0),
          icon: Icons.trending_up,
          color: Colors.green.shade800,
        ),
      ] else
        _SummaryCard(
          label: 'Laba Kotor & HPP',
          value: 'Terkunci',
          icon: Icons.lock_outline,
          color: Colors.grey.shade600,
        ),
    ];

    if (isDesktop) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards
            .map((c) => SizedBox(
                  width: 320,
                  child: c,
                ))
            .toList(),
      );
    } else {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: c,
                ))
            .toList(),
      );
    }
  }

  /// Bagian Produk Terlaris
  Widget _buildTopProductsSection(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final products = report.topProducts;

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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.star_outline, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Produk Terlaris (Top 20)',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                // Toggle Sort
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'qty', label: Text('Qty')),
                    ButtonSegment(value: 'revenue', label: Text('Omzet')),
                  ],
                  selected: {controller.topSellingSortBy.value},
                  onSelectionChanged: (set) {
                    controller.setTopSellingSortBy(set.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Tidak ada produk yang terjual dalam periode ini.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = products[index];
                  final rank = index + 1;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: rank <= 3
                          ? Colors.amber.shade100
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: rank <= 3 ? Colors.amber.shade900 : Colors.black87,
                        ),
                      ),
                    ),
                    title: Text(
                      p.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Terjual: ${p.totalQty} unit',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRupiah(p.totalRevenue),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            fontSize: 14,
                          ),
                        ),
                        if (report.isProfitVisible && p.grossProfit != null)
                          Text(
                            'Laba: ${formatRupiah(p.grossProfit!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Bagian Penjualan per Kategori
  Widget _buildCategorySalesCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final categories = report.categorySales;

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
          children: [
            Row(
              children: [
                Icon(Icons.category_outlined, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Penjualan per Kategori',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Tidak ada data kategori.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              cat.categoryName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          Text(
                            formatRupiah(cat.totalRevenue),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${cat.totalQty} item terjual',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                          Text(
                            '${cat.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (cat.percentage / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Bagian Penjualan per Metode Pembayaran
  Widget _buildPaymentMethodCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final methods = report.paymentMethodSales;

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
          children: [
            Row(
              children: [
                Icon(Icons.payment_outlined, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Metode Pembayaran',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (methods.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Tidak ada transaksi pembayaran.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: methods.length,
                separatorBuilder: (context, index) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final p = methods[index];
                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          _getPaymentIcon(p.method),
                          size: 16,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.method.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${p.txCount} transaksi',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatRupiah(p.totalAmount),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '${p.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  IconData _getPaymentIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
      case 'tunai':
        return Icons.money;
      case 'qris':
        return Icons.qr_code_2;
      case 'transfer':
      case 'debit':
        return Icons.account_balance;
      default:
        return Icons.credit_card;
    }
  }

  /// Bagian Penjualan per Kasir (hanya tampil jika Mode Tim / bukan Solo)
  Widget _buildCashierSalesCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final cashiers = report.cashierSales ?? [];

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
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Penjualan per Kasir',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (cashiers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Tidak ada transaksi kasir pada periode ini.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cashiers.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final c = cashiers[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(
                        c.cashierName.isNotEmpty ? c.cashierName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(c.cashierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('${c.txCount} transaksi (Rata-rata: ${formatRupiah(c.avgPerTx)})', style: const TextStyle(fontSize: 11)),
                    trailing: Text(
                      formatRupiah(c.totalRevenue),
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 13),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Bagian Analisis Jam Ramai (Distribusi Jam 00..23)
  Widget _buildHourlySalesCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final hourly = report.hourlySales;
    final peakHour = hourly.isNotEmpty
        ? hourly.reduce((a, b) => a.txCount >= b.txCount ? a : b)
        : null;

    final hasTransactions = hourly.any((h) => h.txCount > 0);

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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Distribusi Jam & Jam Ramai Toko',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (hasTransactions && peakHour != null && peakHour.txCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      'Jam Tersibuk: ${peakHour.hourLabel} (${peakHour.txCount} tx)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasTransactions)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'Tidak ada transaksi penjualan dalam rentang waktu ini.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: hourly.map((h) {
                    final isPeak = peakHour != null && peakHour.txCount > 0 && h.hour == peakHour.hour;
                    final maxTx = (peakHour?.txCount ?? 1).clamp(1, 999999);
                    final ratio = h.txCount / maxTx;
                    final barHeight = 12.0 + (ratio * 70.0);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Tooltip(
                        message: '${h.hourLabel}\n${h.txCount} transaksi\n${formatRupiah(h.totalRevenue)}',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              h.txCount > 0 ? '${h.txCount}' : '',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isPeak ? Colors.amber.shade900 : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 18,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: isPeak
                                    ? Colors.amber.shade600
                                    : (h.txCount > 0
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.surfaceContainerHighest),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${h.hour}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isPeak ? Colors.amber.shade900 : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isPeak ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bagian Nilai Stok (Valuasi)
  Widget _buildStockValuationCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final val = report.stockValuation;
    final canProfit = report.isProfitVisible && val?.totalCostValue != null;

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
          children: [
            Row(
              children: [
                Icon(Icons.inventory_outlined, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Valuasi Nilai Stok Toko',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildValuationRow('Total Produk Aktif', '${val?.totalProducts ?? 0} SKU'),
            _buildValuationRow('Total Fisik Stok', '${val?.totalStockQty ?? 0} unit'),
            _buildValuationRow('Potensi Omzet (Harga Jual)', formatRupiah(val?.totalRetailValue ?? 0)),
            const Divider(height: 16),
            if (canProfit) ...[
              _buildValuationRow('Nilai Modal Stok (HPP)', formatRupiah(val?.totalCostValue ?? 0), isBold: true),
              _buildValuationRow('Potensi Laba Kotor Stok', formatRupiah(val?.potentialProfit ?? 0), isBold: true, color: Colors.green.shade800),
            ] else
              _buildValuationRow('Modal Stok & Potensi Laba', 'Memerlukan izin laba', color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildValuationRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Bagian Stok Menipis & Habis
  Widget _buildStockAlertsCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final alerts = report.stockAlerts;

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
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Peringatan Stok Menipis & Habis',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stok Habis (0)', style: TextStyle(fontSize: 11, color: Colors.red)),
                        Text('${alerts.outOfStockCount}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stok Menipis', style: TextStyle(fontSize: 11, color: Colors.brown)),
                        Text('${alerts.lowStockCount}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (alerts.outOfStockProducts.isNotEmpty) ...[
              const Text('Daftar Produk Habis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
              ...alerts.outOfStockProducts.take(3).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('• ${p.name}', style: const TextStyle(fontSize: 12)),
                        const Text('Habis (0)', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
            ],
            if (alerts.lowStockProducts.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Daftar Produk Menipis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown)),
              ...alerts.lowStockProducts.take(3).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('• ${p.name}', style: const TextStyle(fontSize: 12)),
                        Text('Sisa ${p.currentStock} ${p.unitName ?? 'unit'}', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
            ],
            if (alerts.outOfStockCount == 0 && alerts.lowStockCount == 0)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Center(
                  child: Text(
                    'Seluruh stok produk dalam batas aman.',
                    style: TextStyle(color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bagian Ringkasan Pembatalan (Void)
  Widget _buildVoidSummaryCard(BuildContext context, FullReportData report) {
    final theme = Theme.of(context);
    final voidSummary = report.voidSummary;

    return Card(
      elevation: 0,
      color: Colors.red.shade50.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.red.shade100,
              child: Icon(Icons.cancel_outlined, color: Colors.red.shade800, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ringkasan Transaksi Dibatalkan (Void)',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${voidSummary.voidCount} transaksi dibatalkan dengan total nominal ${formatRupiah(voidSummary.totalVoidAmount)}.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
