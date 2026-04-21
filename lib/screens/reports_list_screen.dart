import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';
import 'voice_report_screen.dart';

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  String _query = '';
  ReportStatus? _filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'New voice report',
            icon: const Icon(Icons.mic_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: HiveStorageService.reportsListenable(),
              builder: (context, Box<PathologyReport> box, _) {
                final reports =
                    HiveStorageService.allReports().where(_matches).toList();
                if (reports.isEmpty) return _empty();
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => ReportCard(
                    report: reports[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportDetailScreen(
                          report: reports[i],
                          onDeleted: () => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(PathologyReport r) {
    if (_filter != null && r.status != _filter) return false;
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    return r.reportNumber.toLowerCase().contains(q) ||
        r.patientId.toLowerCase().contains(q) ||
        r.patientName.toLowerCase().contains(q) ||
        r.microscopyImpression.toLowerCase().contains(q);
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppColors.surface,
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search by report #, patient ID, name, or impression',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', null),
                _filterChip('Draft', ReportStatus.draft),
                _filterChip('Pending', ReportStatus.pending),
                _filterChip('Completed', ReportStatus.completed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, ReportStatus? status) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 56, color: AppColors.textHint.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text('No reports yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Tap the mic to create your first voice report',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
            ),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('New Voice Report'),
          ),
        ],
      ),
    );
  }
}
