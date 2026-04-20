import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report_models.dart';
import '../theme/app_theme.dart';

class ReportDetailScreen extends StatelessWidget {
  final PathologyReport report;

  const ReportDetailScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(report.reportNumber),
        actions: [
          IconButton(
            onPressed: () => _showExportDialog(context),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Export PDF',
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Report')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'print', child: Text('Print')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Report header
            _buildReportHeader(context),
            const SizedBox(height: 20),

            // Summary card
            if (report.summary.isNotEmpty) ...[
              _buildSummaryCard(context),
              const SizedBox(height: 20),
            ],

            // Patient Info
            _buildDetailCard(
              context,
              title: 'Patient Information',
              icon: Icons.person_rounded,
              children: [
                _DetailRow(label: 'Name', value: report.patient.name),
                _DetailRow(label: 'Age / Gender', value: '${report.patient.age} yrs / ${report.patient.gender}'),
                if (report.patient.contactNumber.isNotEmpty)
                  _DetailRow(label: 'Contact', value: report.patient.contactNumber),
                if (report.patient.referringDoctor.isNotEmpty)
                  _DetailRow(label: 'Referring Doctor', value: report.patient.referringDoctor),
                if (report.patient.hospitalId.isNotEmpty)
                  _DetailRow(label: 'Hospital ID', value: report.patient.hospitalId),
              ],
            ),
            const SizedBox(height: 16),

            // Specimen Info
            _buildDetailCard(
              context,
              title: 'Specimen Details',
              icon: Icons.science_rounded,
              children: [
                _DetailRow(label: 'Type', value: report.specimen.type.label),
                _DetailRow(label: 'Site', value: report.specimen.site),
                if (report.specimen.collectionDate.isNotEmpty)
                  _DetailRow(label: 'Collected', value: report.specimen.collectionDate),
                if (report.specimen.receivedDate.isNotEmpty)
                  _DetailRow(label: 'Received', value: report.specimen.receivedDate),
                if (report.specimen.clinicalHistory.isNotEmpty)
                  _DetailRow(label: 'Clinical History', value: report.specimen.clinicalHistory),
                if (report.specimen.grossDescription.isNotEmpty)
                  _DetailRow(label: 'Gross Description', value: report.specimen.grossDescription),
              ],
            ),
            const SizedBox(height: 16),

            // Pathology Findings
            _buildDetailCard(
              context,
              title: 'Pathology Findings',
              icon: Icons.biotech_rounded,
              children: [
                if (report.findings.microscopicDescription.isNotEmpty)
                  _DetailRow(label: 'Microscopic', value: report.findings.microscopicDescription),
                if (report.findings.diagnosis.isNotEmpty)
                  _DetailRow(
                    label: 'Diagnosis',
                    value: report.findings.diagnosis,
                    highlight: true,
                  ),
                if (report.findings.grade.isNotEmpty)
                  _DetailRow(label: 'Grade', value: report.findings.grade),
                if (report.findings.stage.isNotEmpty)
                  _DetailRow(label: 'Stage', value: report.findings.stage),
              ],
            ),
            const SizedBox(height: 16),

            // Additional Studies
            if (_hasAdditionalStudies()) ...[
              _buildDetailCard(
                context,
                title: 'Additional Studies',
                icon: Icons.hub_rounded,
                children: [
                  if (report.findings.immunohistochemistry.isNotEmpty)
                    _DetailRow(label: 'IHC', value: report.findings.immunohistochemistry),
                  if (report.findings.specialStains.isNotEmpty)
                    _DetailRow(label: 'Special Stains', value: report.findings.specialStains),
                  if (report.findings.molecularStudies.isNotEmpty)
                    _DetailRow(label: 'Molecular Studies', value: report.findings.molecularStudies),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Comments
            if (report.findings.comments.isNotEmpty)
              _buildDetailCard(
                context,
                title: 'Comments',
                icon: Icons.comment_rounded,
                children: [
                  _DetailRow(label: '', value: report.findings.comments),
                ],
              ),

            const SizedBox(height: 20),

            // Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    report.pathologistName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Consultant Pathologist',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Report generated: ${DateFormat('dd MMM yyyy, HH:mm').format(report.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => _showExportDialog(context),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Export PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHeader(BuildContext context) {
    Color statusColor;
    switch (report.status) {
      case ReportStatus.draft:
        statusColor = AppColors.draft;
        break;
      case ReportStatus.pending:
        statusColor = AppColors.pending;
        break;
      case ReportStatus.completed:
        statusColor = AppColors.completed;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.06),
            AppColors.accent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                report.reportNumber,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  report.status.label,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.patient.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${report.patient.age} yrs, ${report.patient.gender} • ${report.specimen.type.label}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Report Summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.success,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  bool _hasAdditionalStudies() {
    return report.findings.immunohistochemistry.isNotEmpty ||
        report.findings.specialStains.isNotEmpty ||
        report.findings.molecularStudies.isNotEmpty;
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Export Report'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose export format:'),
            const SizedBox(height: 16),
            _ExportOption(
              icon: Icons.picture_as_pdf_rounded,
              title: 'PDF Report',
              subtitle: 'Standard pathology report format',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('PDF export — available in full version'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _ExportOption(
              icon: Icons.print_rounded,
              title: 'Print',
              subtitle: 'Send to printer',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _DetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: label.isEmpty
          ? Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: highlight
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            value,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                          ),
                        )
                      : Text(
                          value,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                        ),
                ),
              ],
            ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
