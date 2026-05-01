import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/report_models.dart';
import 'openai_service.dart';

/// Parse an uploaded template file (.docx primarily; .txt as fallback) into
/// a structured `TemplateSchema` of sections → questions → answers.
///
/// Step 1: extract plain text from the file. .docx is a zip — we read
/// `word/document.xml` and pull the `<w:t>` text runs in document order.
/// Step 2: hand the text to OpenAI (`OpenAIService.parseTemplate`) which
/// returns JSON matching the documented schema.
/// Step 3: map JSON → typed dart objects.
class TemplateParserService {
  /// Read a file and extract its plain text. Returns empty string if the
  /// file format is not supported (caller falls back to free-form mode).
  static Future<String> extractText(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Template file not found: $filePath');
    }
    switch (ext) {
      case '.docx':
        return _extractDocxText(await file.readAsBytes());
      case '.txt':
      case '.rtf':
        // RTF is a best-effort here — we strip control words crudely. PDF
        // and .doc are not supported in v1 (the user can re-save as .docx).
        final raw = await file.readAsString();
        return ext == '.rtf' ? _stripRtf(raw) : raw;
      default:
        return '';
    }
  }

  /// Extract paragraph text from a .docx zip in document order.
  /// Each `<w:p>` becomes a line. Tabs / `<w:br>` become `\n`.
  static String _extractDocxText(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = archive.findFile('word/document.xml');
    if (doc == null) return '';
    final xml = utf8.decode(doc.content as List<int>);

    // We do not use a full XML parser here on purpose — the `xml` package is
    // already a transitive dep but the goal is a fast, line-oriented dump
    // that preserves paragraph breaks. The regex finds `<w:p>` blocks,
    // then within each block pulls the text runs.
    final paragraphRegex = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
    final textRunRegex = RegExp(r'<w:t(?:\s[^>]*)?>([^<]*)</w:t>');
    final breakRegex = RegExp(r'<w:br(?:\s[^/]*)?/>');
    final tabRegex = RegExp(r'<w:tab(?:\s[^/]*)?/>');

    final out = StringBuffer();
    for (final pMatch in paragraphRegex.allMatches(xml)) {
      var pXml = pMatch.group(0)!;
      pXml = pXml.replaceAll(breakRegex, '\n');
      pXml = pXml.replaceAll(tabRegex, '\t');
      final line = StringBuffer();
      for (final tMatch in textRunRegex.allMatches(pXml)) {
        line.write(_decodeXmlEntities(tMatch.group(1) ?? ''));
      }
      final text = line.toString();
      // Preserve blank lines (CAP protocols use them as section separators).
      out.writeln(text);
    }
    return out.toString();
  }

  static String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String _stripRtf(String s) {
    // Minimal RTF cleanup: drop control words like \b, \i, \par, etc.
    var t = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    t = t.replaceAll(RegExp(r'[{}]'), '');
    return t.trim();
  }

  /// Parse a template file end-to-end into a `TemplateSchema`. Throws if
  /// extraction yields nothing or the LLM returns malformed JSON.
  static Future<TemplateSchema> parseFile({
    required String filePath,
    required String templateId,
  }) async {
    final text = await extractText(filePath);
    if (text.trim().isEmpty) {
      throw Exception(
          'Could not extract text from this file format. Use .docx for best results.');
    }
    final jsonStr = await OpenAIService.parseTemplate(text);
    return _schemaFromJson(jsonStr, templateId: templateId);
  }

  /// Parse the JSON returned by `OpenAIService.parseTemplate` into typed
  /// objects. Tolerates missing fields and unknown enum values.
  static TemplateSchema _schemaFromJson(String jsonStr,
      {required String templateId}) {
    final dynamic raw = jsonDecode(jsonStr);
    if (raw is! Map<String, dynamic>) {
      throw Exception('Parser returned non-object JSON.');
    }
    final version = (raw['version'] as String?) ?? '';
    final sectionsRaw = (raw['sections'] as List?) ?? const [];
    final sections = <TemplateSection>[];
    for (final s in sectionsRaw) {
      if (s is! Map) continue;
      final title = (s['title'] as String?)?.trim() ?? '';
      final qsRaw = (s['questions'] as List?) ?? const [];
      final qs = <TemplateQuestion>[];
      for (final q in qsRaw) {
        if (q is! Map) continue;
        final question = _questionFromJson(Map<String, dynamic>.from(q));
        if (question != null) qs.add(question);
      }
      sections.add(TemplateSection(title: title, questions: qs));
    }
    return TemplateSchema(
      templateId: templateId,
      version: version,
      sections: sections,
    );
  }

  static TemplateQuestion? _questionFromJson(Map<String, dynamic> q) {
    final id = (q['id'] as String?)?.trim();
    final label = (q['label'] as String?)?.trim();
    if (id == null || id.isEmpty || label == null || label.isEmpty) {
      return null;
    }
    final type = _typeFromString(q['type'] as String?);
    final required = q['required'] is bool ? q['required'] as bool : true;
    final units = (q['units'] as String?) ?? '';
    final freeText = q['free_text_allowed'] is bool
        ? q['free_text_allowed'] as bool
        : false;
    final parentAnswerId = (q['parent_answer_id'] as String?) ?? '';

    final answers = <TemplateAnswer>[];
    final answersRaw = (q['answers'] as List?) ?? const [];
    for (final a in answersRaw) {
      if (a is! Map) continue;
      final aMap = Map<String, dynamic>.from(a);
      final aId = (aMap['id'] as String?)?.trim();
      final aLabel = (aMap['label'] as String?)?.trim();
      if (aId == null || aId.isEmpty || aLabel == null || aLabel.isEmpty) {
        continue;
      }
      answers.add(
        TemplateAnswer(
          id: aId,
          label: aLabel,
          triggersQuestionIds: _stringList(aMap['triggers_question_ids']),
          disablesAnswerIds: _stringList(aMap['disables_answer_ids']),
        ),
      );
    }

    return TemplateQuestion(
      id: id,
      label: label,
      type: type,
      required: required,
      units: units,
      answers: answers,
      freeTextAllowed: freeText,
      parentAnswerId: parentAnswerId,
    );
  }

  static TemplateQuestionType _typeFromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase().replaceAll('-', '_')) {
      case 'multi_select':
      case 'multiselect':
      case 'multi':
        return TemplateQuestionType.multiSelect;
      case 'text':
      case 'free_text':
      case 'string':
        return TemplateQuestionType.text;
      case 'integer':
      case 'int':
      case 'number':
        return TemplateQuestionType.integer;
      case 'decimal':
      case 'float':
      case 'numeric':
        return TemplateQuestionType.decimal;
      case 'date':
      case 'datetime':
        return TemplateQuestionType.date;
      case 'single_select':
      case 'singleselect':
      case 'select':
      case 'radio':
      default:
        return TemplateQuestionType.singleSelect;
    }
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
}
