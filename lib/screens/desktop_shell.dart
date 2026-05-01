import 'dart:async';

import 'package:flutter/material.dart';

import '../models/report_models.dart';
import '../services/hive_storage_service.dart';
import '../services/settings_service.dart';
import '../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'guide_screen.dart';
import 'guided_report_screen.dart';
import 'home_voice_screen.dart';
import 'reports_list_screen.dart';
import 'templates_screen.dart';
import 'voice_report_screen.dart';
import 'voice_settings_screen.dart';

/// Shell with a clickable sidebar (desktop) or bottom nav (mobile) PLUS
/// full voice-command navigation. Either input method works.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

enum _Tab {
  home,
  newReport,
  reports,
  analytics,
  templates,
  guide,
  settings,
}

/// Pairs a template with its parsed schema for the wizard's picker step.
class _TemplateOption {
  final TemplateDocument template;
  final TemplateSchema schema;
  const _TemplateOption({required this.template, required this.schema});
}

class _DesktopShellState extends State<DesktopShell> {
  _Tab _tab = _Tab.home;
  final VoiceCommandService _voice = VoiceCommandService.instance;
  StreamSubscription<VoiceCommandEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _sub = _voice.commands.listen(_onGlobalCommand);
    SettingsService.changes.addListener(_onSettingsChanged);
  }

  Future<void> _initVoice() async {
    final ok = await _voice.init();
    if (ok) await _voice.start();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onGlobalCommand(VoiceCommandEvent e) {
    if (!mounted) return;
    switch (e.command) {
      case VoiceCommand.dashboard:
        _goTo(_Tab.home);
        break;
      case VoiceCommand.newReport:
        _goTo(_Tab.newReport);
        break;
      case VoiceCommand.openReports:
        _goTo(_Tab.reports);
        break;
      case VoiceCommand.openSettings:
        _goTo(_Tab.settings);
        break;
      case VoiceCommand.back:
        if (_tab != _Tab.home) _goTo(_Tab.home);
        break;
      default:
        break;
    }
  }

  void _goTo(_Tab t) {
    if (_tab == t) return;
    setState(() => _tab = t);
  }

  @override
  void dispose() {
    _sub?.cancel();
    SettingsService.changes.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      body: isWide
          ? Row(
              children: [
                _sidebar(),
                const VerticalDivider(width: 1),
                Expanded(child: _animated()),
              ],
            )
          : _animated(),
      bottomNavigationBar: isWide ? null : _bottomNav(),
    );
  }

  Widget _animated() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey(_tab), child: _body()),
    );
  }

  Widget _body() {
    switch (_tab) {
      case _Tab.home:
        return HomeVoiceScreen(
          onNewReport: () => _goTo(_Tab.newReport),
          onShowReports: () => _goTo(_Tab.reports),
          onOpenSettings: () => _goTo(_Tab.settings),
        );
      case _Tab.newReport:
        return _routeNewReport();
      case _Tab.reports:
        return const ReportsListScreen();
      case _Tab.analytics:
        return AnalyticsScreen(onBack: () => _goTo(_Tab.home));
      case _Tab.templates:
        return TemplatesScreen(onBack: () => _goTo(_Tab.home));
      case _Tab.guide:
        return GuideScreen(onBack: () => _goTo(_Tab.home));
      case _Tab.settings:
        return VoiceSettingsScreen(onBack: () => _goTo(_Tab.home));
    }
  }

  /// Decide between the guided wizard and the legacy free-form screen.
  ///
  /// The wizard is used when ANY parsed template exists. It opens with a
  /// template picker (voice or tap); if the doctor doesn't choose one, it
  /// falls back to the active default. With zero parsed templates, the lab
  /// gets the original dictation-only experience — no regression.
  Widget _routeNewReport() {
    final allTemplates = HiveStorageService.allTemplates();
    final usable = <_TemplateOption>[];
    for (final t in allTemplates) {
      final schema = HiveStorageService.getTemplateSchema(t.id);
      if (schema != null && schema.totalQuestions > 0) {
        usable.add(_TemplateOption(template: t, schema: schema));
      }
    }
    if (usable.isEmpty) {
      return VoiceReportScreen(
        onBack: () => _goTo(_Tab.home),
        onReportSaved: (_) => _goTo(_Tab.reports),
      );
    }
    final activeId = SettingsService.getActiveTemplateId();
    final defaultIndex = activeId.isEmpty
        ? 0
        : usable.indexWhere((o) => o.template.id == activeId).clamp(0, usable.length - 1);
    return GuidedReportScreen(
      templates: usable.map((o) => o.template).toList(),
      schemas: {for (final o in usable) o.template.id: o.schema},
      defaultTemplateId: usable[defaultIndex].template.id,
      onBack: () => _goTo(_Tab.home),
      onReportSaved: (_) => _goTo(_Tab.reports),
    );
  }

  // ─── Sidebar (desktop) ──────────────────────────────────

  Widget _sidebar() {
    final activeId = SettingsService.getActiveTemplateId();
    final hasActiveSchema = activeId.isNotEmpty &&
        HiveStorageService.getTemplateSchema(activeId) != null;
    return Container(
      width: 240,
      color: AppColors.surface,
      child: Column(
        children: [
          _brand(),
          _navTile(
            _Tab.home,
            Icons.dashboard_rounded,
            'Home',
          ),
          _navTile(
            _Tab.newReport,
            Icons.mic_rounded,
            'New Voice Report',
            badge: hasActiveSchema ? 'Guided' : null,
          ),
          _navTile(_Tab.reports, Icons.folder_rounded, 'Reports'),
          _navTile(
              _Tab.analytics, Icons.insights_rounded, 'Analytics'),
          _navTile(
              _Tab.templates, Icons.description_rounded, 'Templates'),
          _navTile(_Tab.guide, Icons.menu_book_rounded, 'Guide'),
          _navTile(_Tab.settings, Icons.settings_rounded, 'Settings'),
          const Spacer(),
          _voiceStatusFooter(),
        ],
      ),
    );
  }

  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
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
                  style: Theme.of(context).textTheme.titleLarge),
              Text('Voice + Touch',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navTile(_Tab tab, IconData icon, String label, {String? badge}) {
    final selected = _tab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? AppColors.primary.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _goTo(tab),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      )),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.success)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceStatusFooter() {
    return StreamBuilder<String>(
      stream: _voice.status,
      builder: (context, snap) {
        final listening = _voice.isListening;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: listening ? AppColors.success : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 8),
              Text(listening ? 'Voice listening' : 'Voice idle',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              IconButton(
                iconSize: 18,
                tooltip: listening ? 'Pause listening' : 'Resume listening',
                icon: Icon(listening
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded),
                onPressed: () async {
                  if (listening) {
                    await _voice.stop();
                  } else {
                    await _voice.start();
                  }
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Bottom nav (mobile) ────────────────────────────────

  Widget _bottomNav() {
    // Limit bottom nav to the 5 most-used tabs (NavigationBar caps reasonably
    // at 5 destinations on mobile). Templates / Guide stay reachable from the
    // sidebar on tablet/desktop.
    final destinations = const [
      _Tab.home,
      _Tab.newReport,
      _Tab.reports,
      _Tab.analytics,
      _Tab.settings,
    ];
    final selectedIndex = destinations.indexOf(_tab).clamp(0, destinations.length - 1);
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => _goTo(destinations[i]),
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home'),
        NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Dictate'),
        NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Reports'),
        NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Analytics'),
        NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings'),
      ],
    );
  }
}
