import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';

/// Analytics dashboard backed entirely by the local Hive `reports` box —
/// no new schema, no new service. Three charts (reports/day bar, status pie,
/// turnaround trend line) plus a simple keyword-frequency view of the
/// dictated impressions.
class AnalyticsScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const AnalyticsScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: HiveStorageService.reportsListenable(),
                builder: (context, Box<PathologyReport> box, _) {
                  final reports = HiveStorageService.allReports();
                  if (reports.isEmpty) return _empty(context);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _periodStats(reports),
                        const SizedBox(height: 16),
                        LayoutBuilder(builder: (_, c) {
                          final wide = c.maxWidth > 820;
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        flex: 6,
                                        child: _card(
                                            'Reports per day (last 30)',
                                            _reportsPerDayChart(reports))),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        flex: 4,
                                        child: _card('Status distribution',
                                            _statusPie(reports))),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _card('Reports per day (last 30)',
                                        _reportsPerDayChart(reports)),
                                    const SizedBox(height: 16),
                                    _card('Status distribution',
                                        _statusPie(reports)),
                                  ],
                                );
                        }),
                        const SizedBox(height: 16),
                        LayoutBuilder(builder: (_, c) {
                          final wide = c.maxWidth > 820;
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: _card(
                                            'Turnaround time (days, by week)',
                                            _turnaroundLine(reports))),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _card('Top diagnoses',
                                            _diagnosesChart(reports))),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _card('Turnaround time (days, by week)',
                                        _turnaroundLine(reports)),
                                    const SizedBox(height: 16),
                                    _card('Top diagnoses',
                                        _diagnosesChart(reports)),
                                  ],
                                );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── chrome ──────────────────────────────────────────────────

  Widget _topBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          const Icon(Icons.insights_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('Analytics', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Aggregated from your local reports — updates live as you save.',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded,
              size: 56, color: AppColors.textHint.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text('No reports yet — save one to populate analytics.',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _card(String title, Widget body) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(height: 240, child: body),
        ],
      ),
    );
  }

  // ─── period stats with delta vs previous period ────────────────

  Widget _periodStats(List<PathologyReport> reports) {
    final now = DateTime.now();
    int countSince(DateTime start, DateTime end) =>
        reports
            .where((r) =>
                r.createdAt.isAfter(start) && r.createdAt.isBefore(end))
            .length;
    final week = countSince(now.subtract(const Duration(days: 7)), now);
    final prevWeek = countSince(
        now.subtract(const Duration(days: 14)),
        now.subtract(const Duration(days: 7)));
    final month = countSince(now.subtract(const Duration(days: 30)), now);
    final prevMonth = countSince(
        now.subtract(const Duration(days: 60)),
        now.subtract(const Duration(days: 30)));
    final year = reports.where((r) => r.createdAt.year == now.year).length;

    Widget cell(String title, int value, int? prev) {
      String delta = '';
      Color deltaColor = AppColors.textHint;
      if (prev != null) {
        final diff = value - prev;
        if (diff > 0) {
          delta = '↑ $diff';
          deltaColor = AppColors.success;
        } else if (diff < 0) {
          delta = '↓ ${-diff}';
          deltaColor = AppColors.error;
        } else {
          delta = '·';
        }
      }
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.textHint)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$value',
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(delta,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: deltaColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.description_rounded,
            title: 'Total Reports',
            value: '${reports.length}',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        cell('This Week', week, prevWeek),
        const SizedBox(width: 12),
        cell('This Month', month, prevMonth),
        const SizedBox(width: 12),
        cell('This Year', year, null),
      ],
    );
  }

  // ─── reports per day bar chart ─────────────────────────────────

  Widget _reportsPerDayChart(List<PathologyReport> reports) {
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
    final buckets = List<int>.filled(30, 0);
    for (final r in reports) {
      final d = DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day);
      final diff = d.difference(start).inDays;
      if (diff >= 0 && diff < 30) buckets[diff]++;
    }
    final maxY =
        (buckets.fold<int>(0, (m, v) => v > m ? v : m) + 1).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              getTitlesWidget: (v, _) {
                final d = start.add(Duration(days: v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d/M').format(d),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textHint)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                    toY: buckets[i].toDouble(),
                    color: AppColors.primary,
                    width: 6,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(2))),
              ],
            ),
        ],
      ),
    );
  }

  // ─── status pie ────────────────────────────────────────────────

  Widget _statusPie(List<PathologyReport> reports) {
    final draft = reports.where((r) => r.status == ReportStatus.draft).length;
    final pending =
        reports.where((r) => r.status == ReportStatus.pending).length;
    final completed =
        reports.where((r) => r.status == ReportStatus.completed).length;
    final total = reports.length.toDouble();
    if (total == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                if (draft > 0)
                  PieChartSectionData(
                    value: draft.toDouble(),
                    color: AppColors.draft,
                    title: '${(draft / total * 100).round()}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                if (pending > 0)
                  PieChartSectionData(
                    value: pending.toDouble(),
                    color: AppColors.pending,
                    title: '${(pending / total * 100).round()}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                if (completed > 0)
                  PieChartSectionData(
                    value: completed.toDouble(),
                    color: AppColors.completed,
                    title: '${(completed / total * 100).round()}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legend('Draft', AppColors.draft, draft),
              _legend('Pending', AppColors.pending, pending),
              _legend('Completed', AppColors.completed, completed),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(String label, Color c, int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 10, height: 10, color: c),
          const SizedBox(width: 8),
          Text('$label · $n',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ─── turnaround line chart ─────────────────────────────────────

  Widget _turnaroundLine(List<PathologyReport> reports) {
    if (reports.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final weeks = 12; // last 12 weeks
    final startWeek =
        DateTime(now.year, now.month, now.day - now.weekday + 1)
            .subtract(Duration(days: 7 * (weeks - 1)));
    final sums = List<double>.filled(weeks, 0);
    final counts = List<int>.filled(weeks, 0);
    for (final r in reports) {
      final w = r.reportedDate.difference(startWeek).inDays ~/ 7;
      if (w < 0 || w >= weeks) continue;
      final tatDays =
          r.reportedDate.difference(r.sampleReceiptDate).inHours / 24.0;
      if (tatDays < 0 || tatDays > 365) continue;
      sums[w] += tatDays;
      counts[w]++;
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < weeks; i++) {
      if (counts[i] > 0) spots.add(FlSpot(i.toDouble(), sums[i] / counts[i]));
    }
    if (spots.isEmpty) {
      return Center(
        child: Text('Not enough data yet to compute turnaround trend.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textHint)),
      );
    }
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              getTitlesWidget: (v, _) {
                final d = startWeek.add(Duration(days: 7 * v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d/M').format(d),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textHint)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppColors.primary,
            barWidth: 2.4,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primary.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }

  // ─── top diagnoses (keyword frequency) ─────────────────────────

  Widget _diagnosesChart(List<PathologyReport> reports) {
    const keywords = [
      'adenocarcinoma',
      'squamous cell carcinoma',
      'invasive ductal',
      'invasive lobular',
      'lymphoma',
      'melanoma',
      'sarcoma',
      'benign',
      'fibroadenoma',
      'in situ',
      'metastatic',
      'dysplasia',
    ];
    final counts = <String, int>{for (final k in keywords) k: 0};
    for (final r in reports) {
      final hay =
          '${r.microscopyImpression} ${r.summary} ${r.specimen}'.toLowerCase();
      for (final k in keywords) {
        if (hay.contains(k)) counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();
    if (top.isEmpty) {
      return Center(
        child: Text(
          'No diagnoses detected — keyword frequency will populate as reports are saved.',
          style: TextStyle(fontSize: 12, color: AppColors.textHint),
          textAlign: TextAlign.center,
        ),
      );
    }
    final maxV =
        top.fold<int>(0, (m, e) => e.value > m ? e.value : m).toDouble();
    return ListView.separated(
      itemCount: top.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = top[i];
        final pct = e.value / maxV;
        return Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(e.key,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 12,
                  backgroundColor: AppColors.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              child: Text('${e.value}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }
}
