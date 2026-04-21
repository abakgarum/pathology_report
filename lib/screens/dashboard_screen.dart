import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/report_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/section_header.dart';
import 'report_detail_screen.dart';
import 'voice_report_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: HiveStorageService.reportsListenable(),
          builder: (context, Box<PathologyReport> box, _) {
            final reports = HiveStorageService.allReports();
            final completed = reports
                .where((r) => r.status == ReportStatus.completed)
                .length;
            final pending =
                reports.where((r) => r.status == ReportStatus.pending).length;
            final drafts =
                reports.where((r) => r.status == ReportStatus.draft).length;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Row(
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
                        Expanded(
                          child: StatCard(
                            icon: Icons.check_circle_rounded,
                            title: 'Completed',
                            value: '$completed',
                            color: AppColors.completed,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.hourglass_top_rounded,
                            title: 'Pending',
                            value: '$pending',
                            color: AppColors.pending,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.edit_note_rounded,
                            title: 'Drafts',
                            value: '$drafts',
                            color: AppColors.draft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child:
                        SectionHeader(title: 'Recent Reports'),
                  ),
                ),
                reports.isEmpty
                    ? SliverFillRemaining(child: _empty(context))
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: reports.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => ReportCard(
                            report: reports[i],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportDetailScreen(
                                  report: reports[i],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
        ),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('New Report'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.biotech_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PathLab Pro',
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('Histopathology Suite',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
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
          Icon(Icons.inbox_outlined,
              size: 56, color: AppColors.textHint.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text('No reports yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceReportScreen()),
            ),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Create First Report'),
          ),
        ],
      ),
    );
  }
}
