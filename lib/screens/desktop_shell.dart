import 'package:flutter/material.dart';
import '../models/report_models.dart';
import '../theme/app_theme.dart';
import '../utils/demo_data.dart';
import '../widgets/report_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/section_header.dart';
import 'voice_report_screen.dart';
import 'report_detail_screen.dart';
import 'reports_list_screen.dart';

/// Desktop-first shell: sidebar nav + content area. No screen transitions.
/// Everything loads inside panels for a seamless doctor workflow.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _selectedNav = 0; // 0=Dashboard, 1=NewVoiceReport, 2=Reports, 3=Settings
  PathologyReport? _selectedReport;
  List<PathologyReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _reports = DemoData.getSampleReports();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    if (!isWide) {
      return _buildMobileLayout();
    }
    return _buildDesktopLayout();
  }

  // ─── DESKTOP: Sidebar + Content ────────────────────────────────

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          const VerticalDivider(width: 1),
          // Main content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: AppColors.surface,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.biotech_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PathLab Pro',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        )),
                    Text('Pathology Suite',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        )),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Nav items
          _SidebarItem(
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
            isSelected: _selectedNav == 0,
            onTap: () => setState(() {
              _selectedNav = 0;
              _selectedReport = null;
            }),
          ),
          _SidebarItem(
            icon: Icons.mic_rounded,
            label: 'New Voice Report',
            isSelected: _selectedNav == 1,
            onTap: () => setState(() {
              _selectedNav = 1;
              _selectedReport = null;
            }),
            badge: 'NEW',
            badgeColor: AppColors.accent,
          ),
          _SidebarItem(
            icon: Icons.description_rounded,
            label: 'All Reports',
            isSelected: _selectedNav == 2,
            onTap: () => setState(() {
              _selectedNav = 2;
              _selectedReport = null;
            }),
            badge: '${_reports.length}',
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.border),
          ),
          const SizedBox(height: 8),

          _SidebarItem(
            icon: Icons.text_snippet_rounded,
            label: 'Quick Templates',
            isSelected: _selectedNav == 3,
            onTap: () => setState(() => _selectedNav = 3),
          ),
          _SidebarItem(
            icon: Icons.analytics_rounded,
            label: 'Analytics',
            isSelected: _selectedNav == 4,
            onTap: () => setState(() => _selectedNav = 4),
          ),
          _SidebarItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            isSelected: _selectedNav == 5,
            onTap: () => setState(() => _selectedNav = 5),
          ),

          const Spacer(),

          // Doctor profile at bottom
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  child: const Text('AP',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dr. Anand Patel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      Text('Pathologist',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // If a report is selected from dashboard/list, show it in detail
    if (_selectedReport != null) {
      return ReportDetailScreen(report: _selectedReport!);
    }

    switch (_selectedNav) {
      case 0:
        return _buildDashboardContent();
      case 1:
        return VoiceReportScreen(
          onReportSaved: (report) {
            setState(() {
              _reports.insert(0, report);
              _selectedNav = 0;
            });
          },
        );
      case 2:
        return _buildReportsListContent();
      case 3:
        return _buildPlaceholder('Quick Templates',
            'Create reusable text macros for common findings.', Icons.text_snippet_rounded);
      case 4:
        return _buildPlaceholder('Analytics',
            'View report statistics and trends.', Icons.analytics_rounded);
      case 5:
        return _buildSettingsContent();
      default:
        return _buildDashboardContent();
    }
  }

  // ─── Dashboard Content ─────────────────────────────────────────

  Widget _buildDashboardContent() {
    final completed = _reports.where((r) => r.status == ReportStatus.completed).length;
    final pending = _reports.where((r) => r.status == ReportStatus.pending).length;
    final drafts = _reports.where((r) => r.status == ReportStatus.draft).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good Morning, Dr. Patel',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text("Here's your pathology overview for today.",
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
              const Spacer(),
              // Quick voice report button
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedNav = 1),
                icon: const Icon(Icons.mic_rounded, size: 20),
                label: const Text('New Voice Report'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stats row
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: 'Total Reports',
                  value: '${_reports.length}',
                  icon: Icons.description_rounded,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  title: 'Completed',
                  value: '$completed',
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  title: 'Pending Review',
                  value: '$pending',
                  icon: Icons.hourglass_top_rounded,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  title: 'Drafts',
                  value: '$drafts',
                  icon: Icons.edit_note_rounded,
                  color: AppColors.draft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Voice report CTA card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primaryLight,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.mic_rounded,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice-Powered Reports',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Just dictate your findings — AI transcribes in real-time and generates a complete structured pathology report. Review the raw recording anytime.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () => setState(() => _selectedNav = 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 16),
                  ),
                  child: const Text('Start Dictating'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Recent reports
          SectionHeader(
            title: 'Recent Reports',
            icon: Icons.history_rounded,
            trailing: TextButton(
              onPressed: () => setState(() => _selectedNav = 2),
              child: const Text('View All'),
            ),
          ),
          const SizedBox(height: 8),
          ..._reports.take(4).map((report) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ReportCard(
                  report: report,
                  onTap: () => setState(() => _selectedReport = report),
                ),
              )),
        ],
      ),
    );
  }

  // ─── Reports List Content ──────────────────────────────────────

  Widget _buildReportsListContent() {
    return ReportsListScreen(
      reports: _reports,
      onReportTap: (report) => setState(() => _selectedReport = report),
    );
  }

  // ─── Settings Content ──────────────────────────────────────────

  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 24),
          // Profile card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: const Text('AP',
                      style: TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. Anand Patel',
                        style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Consultant Pathologist — MD, DNB',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8), fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _settingsTile(Icons.person_outline, 'Profile', 'Edit your professional details'),
          _settingsTile(Icons.local_hospital_outlined, 'Lab Information', 'Hospital / Lab details for report headers'),
          _settingsTile(Icons.format_paint_outlined, 'Report Templates', 'Customize report layouts'),
          _settingsTile(Icons.mic_outlined, 'Voice & Transcription', 'STT engine, language, auto-correct settings'),
          _settingsTile(Icons.cloud_outlined, 'Backup & Sync', 'Cloud backup settings'),
          _settingsTile(Icons.security_outlined, 'Privacy & Security', 'PIN, biometrics, encryption'),
          _settingsTile(Icons.info_outline, 'About', 'PathLab Pro v1.0.0'),
        ],
      ),
    );
  }

  Widget _settingsTile(IconData icon, String title, String sub) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 22),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(sub, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: () {},
    );
  }

  Widget _buildPlaceholder(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textHint.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.textHint)),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  // ─── Mobile fallback ───────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Scaffold(
      body: IndexedStack(
        index: _selectedNav > 2 ? 0 : _selectedNav,
        children: [
          _buildDashboardContent(),
          VoiceReportScreen(
            onReportSaved: (report) {
              setState(() {
                _reports.insert(0, report);
                _selectedNav = 0;
              });
            },
          ),
          _buildReportsListContent(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNav > 2 ? 0 : _selectedNav,
        onDestinationSelected: (i) => setState(() => _selectedNav = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_outlined),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Voice Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description_rounded),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar Nav Item ────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.primary.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? AppColors.textHint).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeColor ?? AppColors.textHint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
