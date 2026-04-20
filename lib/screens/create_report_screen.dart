import 'package:flutter/material.dart';
import '../models/report_models.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import 'report_detail_screen.dart';

class CreateReportScreen extends StatefulWidget {
  const CreateReportScreen({super.key});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  int _currentStep = 0;
  SpecimenType _selectedSpecimenType = SpecimenType.biopsy;

  // Patient controllers
  final _patientNameCtrl = TextEditingController();
  final _patientAgeCtrl = TextEditingController();
  String _selectedGender = 'Male';
  final _contactCtrl = TextEditingController();
  final _referringDrCtrl = TextEditingController();
  final _hospitalIdCtrl = TextEditingController();

  // Specimen controllers
  final _siteCtrl = TextEditingController();
  final _collectionDateCtrl = TextEditingController();
  final _receivedDateCtrl = TextEditingController();
  final _clinicalHistoryCtrl = TextEditingController();
  final _grossDescCtrl = TextEditingController();

  // Findings controllers
  final _microscopicCtrl = TextEditingController();
  final _diagnosisCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _stageCtrl = TextEditingController();
  final _ihcCtrl = TextEditingController();
  final _specialStainsCtrl = TextEditingController();
  final _molecularCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _patientNameCtrl, _patientAgeCtrl, _contactCtrl, _referringDrCtrl,
      _hospitalIdCtrl, _siteCtrl, _collectionDateCtrl, _receivedDateCtrl,
      _clinicalHistoryCtrl, _grossDescCtrl, _microscopicCtrl, _diagnosisCtrl,
      _gradeCtrl, _stageCtrl, _ihcCtrl, _specialStainsCtrl, _molecularCtrl,
      _commentsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Report'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Draft'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),
          // Form content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStep(),
            ),
          ),
          // Navigation buttons
          _buildNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Patient', 'Specimen', 'Findings', 'Review'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;
          return Expanded(
            child: Row(
              children: [
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isCompleted || isActive
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.primary
                        : isActive
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: AppColors.primaryLight, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : AppColors.textHint,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isCompleted ? AppColors.primary : AppColors.border,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildPatientStep();
      case 1:
        return _buildSpecimenStep();
      case 2:
        return _buildFindingsStep();
      case 3:
        return _buildReviewStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPatientStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Patient Information', icon: Icons.person_rounded),
        _buildTextField(_patientNameCtrl, 'Full Name', Icons.person_outline),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildTextField(_patientAgeCtrl, 'Age', Icons.cake_outlined,
                  keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildDropdown(
                'Gender',
                _selectedGender,
                ['Male', 'Female', 'Other'],
                (val) => setState(() => _selectedGender = val!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildTextField(_contactCtrl, 'Contact Number', Icons.phone_outlined,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 14),
        _buildTextField(
            _referringDrCtrl, 'Referring Doctor', Icons.medical_services_outlined),
        const SizedBox(height: 14),
        _buildTextField(_hospitalIdCtrl, 'Hospital / Lab ID', Icons.badge_outlined),
      ],
    );
  }

  Widget _buildSpecimenStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Specimen Details', icon: Icons.science_rounded),
        Text('Specimen Type', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SpecimenType.values.map((type) {
            final isSelected = type == _selectedSpecimenType;
            return ChoiceChip(
              label: Text(type.label),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedSpecimenType = type);
              },
              selectedColor: AppColors.primary.withOpacity(0.15),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        _buildTextField(_siteCtrl, 'Specimen Site / Source', Icons.pin_drop_outlined),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _collectionDateCtrl,
                'Collection Date',
                Icons.calendar_today_outlined,
                readOnly: true,
                onTap: () => _pickDate(_collectionDateCtrl),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildTextField(
                _receivedDateCtrl,
                'Received Date',
                Icons.calendar_today_outlined,
                readOnly: true,
                onTap: () => _pickDate(_receivedDateCtrl),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _clinicalHistoryCtrl,
          'Clinical History & Indication',
          Icons.history_rounded,
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _grossDescCtrl,
          'Gross Description',
          Icons.visibility_outlined,
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _buildFindingsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Pathology Findings',
          icon: Icons.biotech_rounded,
        ),
        _buildTextField(
          _microscopicCtrl,
          'Microscopic Description',
          Icons.mic_none_sharp,
          maxLines: 5,
          hint: 'Describe the microscopic features observed...',
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _diagnosisCtrl,
          'Diagnosis',
          Icons.local_hospital_outlined,
          maxLines: 2,
          hint: 'Final pathological diagnosis...',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildTextField(_gradeCtrl, 'Grade', Icons.grade_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildTextField(_stageCtrl, 'Stage', Icons.layers_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Additional Studies',
          icon: Icons.science_outlined,
        ),
        _buildTextField(
          _ihcCtrl,
          'Immunohistochemistry (IHC)',
          Icons.grid_view_rounded,
          maxLines: 3,
          hint: 'e.g., TTF-1: Positive, CK7: Positive...',
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _specialStainsCtrl,
          'Special Stains',
          Icons.color_lens_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _molecularCtrl,
          'Molecular Studies',
          Icons.hub_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          _commentsCtrl,
          'Comments / Notes',
          Icons.comment_outlined,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Review & Generate', icon: Icons.rate_review_rounded),
        // Summary card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.05),
                AppColors.accent.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'AI-Generated Summary',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _generateSummary(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Review details
        _ReviewSection(
          title: 'Patient',
          items: {
            'Name': _patientNameCtrl.text.isEmpty ? 'Not provided' : _patientNameCtrl.text,
            'Age / Gender': '${_patientAgeCtrl.text.isEmpty ? '-' : _patientAgeCtrl.text} / $_selectedGender',
            'Referring Doctor': _referringDrCtrl.text.isEmpty ? 'Not provided' : _referringDrCtrl.text,
          },
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'Specimen',
          items: {
            'Type': _selectedSpecimenType.label,
            'Site': _siteCtrl.text.isEmpty ? 'Not provided' : _siteCtrl.text,
            'Collection Date': _collectionDateCtrl.text.isEmpty ? 'Not set' : _collectionDateCtrl.text,
          },
        ),
        const SizedBox(height: 14),
        _ReviewSection(
          title: 'Findings',
          items: {
            'Diagnosis': _diagnosisCtrl.text.isEmpty ? 'Not provided' : _diagnosisCtrl.text,
            'Grade': _gradeCtrl.text.isEmpty ? '-' : _gradeCtrl.text,
            'Stage': _stageCtrl.text.isEmpty ? '-' : _stageCtrl.text,
          },
        ),
      ],
    );
  }

  String _generateSummary() {
    final parts = <String>[];
    if (_patientNameCtrl.text.isNotEmpty) {
      parts.add('Patient ${_patientNameCtrl.text}');
      if (_patientAgeCtrl.text.isNotEmpty) {
        parts.add('(${_patientAgeCtrl.text}y $_selectedGender)');
      }
    }
    if (_siteCtrl.text.isNotEmpty) {
      parts.add('— ${_selectedSpecimenType.label} from ${_siteCtrl.text}.');
    }
    if (_diagnosisCtrl.text.isNotEmpty) {
      parts.add('Diagnosis: ${_diagnosisCtrl.text}.');
    }
    if (_gradeCtrl.text.isNotEmpty) {
      parts.add('Grade: ${_gradeCtrl.text}.');
    }
    if (_ihcCtrl.text.isNotEmpty) {
      parts.add('IHC: ${_ihcCtrl.text}.');
    }
    if (_commentsCtrl.text.isNotEmpty) {
      parts.add(_commentsCtrl.text);
    }
    if (parts.isEmpty) {
      return 'Fill in the report details to generate an automated summary. The summary will compile patient information, specimen details, diagnosis, and key findings into a concise clinical narrative.';
    }
    return parts.join(' ');
  }

  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
            ),
          const Spacer(),
          if (_currentStep < 3)
            ElevatedButton.icon(
              onPressed: () => setState(() => _currentStep++),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Next'),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _generateReport(),
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: maxLines == 1 ? Icon(icon, size: 20) : null,
        icon: maxLines > 1 ? Icon(icon, size: 20) : null,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.wc_outlined, size: 20),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      controller.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  void _generateReport() {
    final report = PathologyReport(
      reportNumber: 'PATH-2026-0045',
      patient: Patient(
        name: _patientNameCtrl.text.isEmpty ? 'Demo Patient' : _patientNameCtrl.text,
        age: int.tryParse(_patientAgeCtrl.text) ?? 0,
        gender: _selectedGender,
        contactNumber: _contactCtrl.text,
        referringDoctor: _referringDrCtrl.text,
        hospitalId: _hospitalIdCtrl.text,
      ),
      specimen: Specimen(
        type: _selectedSpecimenType,
        site: _siteCtrl.text,
        collectionDate: _collectionDateCtrl.text,
        receivedDate: _receivedDateCtrl.text,
        clinicalHistory: _clinicalHistoryCtrl.text,
        grossDescription: _grossDescCtrl.text,
      ),
      findings: PathologyFinding(
        microscopicDescription: _microscopicCtrl.text,
        diagnosis: _diagnosisCtrl.text,
        grade: _gradeCtrl.text,
        stage: _stageCtrl.text,
        immunohistochemistry: _ihcCtrl.text,
        specialStains: _specialStainsCtrl.text,
        molecularStudies: _molecularCtrl.text,
        comments: _commentsCtrl.text,
      ),
      status: ReportStatus.completed,
      pathologistName: 'Dr. Anand Patel',
      summary: _generateSummary(),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(report: report),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final Map<String, String> items;

  const _ReviewSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                ),
          ),
          const SizedBox(height: 10),
          ...items.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
