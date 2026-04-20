import 'package:flutter/material.dart';
import '../models/report_models.dart';
import '../theme/app_theme.dart';
import '../utils/demo_data.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';

class ReportsListScreen extends StatefulWidget {
  final List<PathologyReport>? reports;
  final ValueChanged<PathologyReport>? onReportTap;

  const ReportsListScreen({
    super.key,
    this.reports,
    this.onReportTap,
  });

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  ReportStatus? _filterStatus;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allReports = widget.reports ?? DemoData.getSampleReports();
    final filtered = allReports.where((r) {
      final matchesStatus = _filterStatus == null || r.status == _filterStatus;
      final matchesSearch = _searchQuery.isEmpty ||
          r.patient.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.reportNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.findings.diagnosis.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesStatus && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Text('All Reports',
                style: Theme.of(context).textTheme.headlineLarge),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search by patient, report #, or diagnosis...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _filterStatus == null,
                  onTap: () => setState(() => _filterStatus = null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Completed',
                  isSelected: _filterStatus == ReportStatus.completed,
                  color: AppColors.completed,
                  onTap: () => setState(() => _filterStatus = ReportStatus.completed),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pending',
                  isSelected: _filterStatus == ReportStatus.pending,
                  color: AppColors.pending,
                  onTap: () => setState(() => _filterStatus = ReportStatus.pending),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Draft',
                  isSelected: _filterStatus == ReportStatus.draft,
                  color: AppColors.draft,
                  onTap: () => setState(() => _filterStatus = ReportStatus.draft),
                ),
                const Spacer(),
                Text(
                  '${filtered.length} report${filtered.length != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // Report list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text('No reports found',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.textHint)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ReportCard(
                          report: filtered[index],
                          onTap: () {
                            if (widget.onReportTap != null) {
                              widget.onReportTap!(filtered[index]);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReportDetailScreen(
                                      report: filtered[index]),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
