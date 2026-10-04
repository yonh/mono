import 'package:pdfrx/pdfrx.dart';

import '../models.dart';

/// AI 上下文范围。
enum ContextScope { selection, page, chapter, document }

extension ContextScopeLabel on ContextScope {
  String get label => switch (this) {
    ContextScope.selection => '选中文本',
    ContextScope.page => '当前页',
    ContextScope.chapter => '本章节',
    ContextScope.document => '整篇文档',
  };
}

/// 取某一页全文。
Future<String> pageFullText(PdfDocument doc, int pageNumber) async {
  if (pageNumber < 1 || pageNumber > doc.pages.length) return '';
  final t = await doc.pages[pageNumber - 1].loadStructuredText();
  return t.fullText;
}

/// 展开大纲为 [(标题, 起始页)]，按页码排序。
List<({String title, int page})> flattenOutline(List<PdfOutlineNode>? outline) {
  final out = <({String title, int page})>[];
  void walk(List<PdfOutlineNode>? nodes) {
    if (nodes == null) return;
    for (final n in nodes) {
      final p = n.dest?.pageNumber;
      out.add((title: n.title, page: p ?? 1));
      walk(n.children);
    }
  }

  walk(outline);
  out.sort((a, b) => a.page.compareTo(b.page));
  return out;
}

/// 当前页所属章节的页范围：[startPage, endPage)（endPage 为下一章节起始页或页数+1）。
({int start, int end, String title}) chapterRangeFor(
  List<({String title, int page})> flat,
  int currentPage,
  int pageCount,
) {
  var start = 1;
  var end = pageCount + 1;
  var title = '';
  for (var i = 0; i < flat.length; i++) {
    final it = flat[i];
    if (it.page <= currentPage && it.page >= start) {
      start = it.page;
      title = it.title;
    }
    if (it.page > currentPage && it.page < end) {
      end = it.page;
    }
  }
  return (start: start, end: end, title: title);
}

/// 组装上下文文本，按 cap 截断并注明截断处。
class DocContext {
  DocContext({
    required this.text,
    required this.scope,
    this.chapterTitle = '',
    this.truncated = false,
  });

  final String text;
  final ContextScope scope;
  final String chapterTitle;
  final bool truncated;
}

Future<DocContext> buildContext({
  required PdfDocument doc,
  required ContextScope scope,
  required int currentPage,
  String selection = '',
  List<PdfOutlineNode>? outline,
  int cap = 24000,
}) async {
  var text = '';
  var chapterTitle = '';
  var truncated = false;

  String clip(String s) {
    if (s.length <= cap) return s;
    truncated = true;
    return '${s.substring(0, cap)}\n…[内容过长已截断]';
  }

  switch (scope) {
    case ContextScope.selection:
      text = selection;
    case ContextScope.page:
      text = await pageFullText(doc, currentPage);
    case ContextScope.chapter:
      final r = chapterRangeFor(
        flattenOutline(outline),
        currentPage,
        doc.pages.length,
      );
      chapterTitle = r.title;
      final b = StringBuffer();
      final maxPages = (r.end - r.start).clamp(0, 30);
      for (
        var p = r.start;
        p < r.start + maxPages && p <= doc.pages.length;
        p++
      ) {
        b.writeln('\n[第 $p 页]');
        b.writeln(await pageFullText(doc, p));
        if (b.length > cap * 2) break;
      }
      if (r.end - r.start > maxPages) truncated = true;
      text = b.toString();
    case ContextScope.document:
      final flat = flattenOutline(outline);
      final b = StringBuffer();
      if (flat.isNotEmpty) {
        b.writeln('【目录结构】');
        for (final f in flat.take(200)) {
          b.writeln('p${f.page} ${f.title}');
        }
        b.writeln('【正文摘录】');
      }
      final pageCount = doc.pages.length;
      // 采样式摘录：最多 40 页均匀取样，每页截 1500 字
      final step = (pageCount / 40).ceil().clamp(1, pageCount);
      for (var p = 1; p <= pageCount; p += step) {
        final t = await pageFullText(doc, p);
        b.writeln('\n[第 $p 页]');
        b.writeln(t.length > 1500 ? t.substring(0, 1500) : t);
        if (b.length > cap * 2) break;
      }
      truncated = pageCount > 40;
      text = b.toString();
  }
  return DocContext(
    text: clip(text),
    scope: scope,
    chapterTitle: chapterTitle,
    truncated: truncated,
  );
}

/// 快捷动作 → 构造好的 messages。
class Prompts {
  static const system =
      '你是嵌入在 PDF 学习阅读器里的学习助手。用简体中文回答（除非用户用其他语言提问或要求翻译）。'
      '回答要准确、结构清晰、贴合给出的文档上下文；上下文不足时明确说明，不要编造。'
      '适当使用 Markdown 列表和小标题，避免冗长。';

  static List<ChatMessage> action(
    String action,
    DocContext ctx, {
    String question = '',
  }) {
    final scopeDesc =
        ctx.scope == ContextScope.chapter && ctx.chapterTitle.isNotEmpty
        ? '${ctx.scope.label}《${ctx.chapterTitle}》'
        : ctx.scope.label;
    final truncNote = ctx.truncated ? '（注意：内容已截断，如需更完整可缩小范围）' : '';
    final ctxBlock =
        '以下是从 PDF 中提取的$scopeDesc内容$truncNote：\n"""\n${ctx.text}\n"""\n';

    final String task;
    switch (action) {
      case 'explain':
        task = '请用通俗易懂的方式讲解这段内容：先一句话概括，再分点展开关键概念、逻辑关系和值得注意的细节，必要时补充背景知识帮助理解。';
      case 'translate':
        task = '请将这段内容翻译成流畅自然的中文（保持术语准确，保留专有名词原文括注）。若原文已是中文，则翻译成英文。';
      case 'summarize':
        task = '请总结这段内容：给出 1-2 句总述，然后用要点列出核心结论/论据，最后指出潜在的疑问或值得深读的部分。';
      case 'note':
        task = '请把这段内容整理成结构化的学习笔记：标题层级 + 要点 + 关键术语解释 + 可能的考点。直接输出笔记内容。';
      case 'quiz':
        task =
            '基于这段内容出复习题。只输出 JSON（不要任何多余文字、不要代码块包裹）：'
            '{"cards":[{"front":"问题或提示","back":"答案要点","page":页码或null}]}，'
            '生成 8-15 张卡片，覆盖核心概念、易混点与关键事实。';
      default:
        task = question;
    }

    return [
      ChatMessage(role: 'system', content: system),
      ChatMessage(role: 'user', content: '$ctxBlock$task'),
    ];
  }

  /// 自由问答：携带上下文 + 历史。
  static List<ChatMessage> chat(
    DocContext ctx,
    List<ChatMessage> history,
    String question,
  ) {
    final scopeDesc = ctx.scope.label;
    return [
      ChatMessage(role: 'system', content: system),
      ChatMessage(
        role: 'user',
        content:
            '当前文档上下文（$scopeDesc）：\n"""\n${ctx.text}\n"""\n基于上下文优先回答，必要时结合常识。',
      ),
      ...history.take(20),
      ChatMessage(role: 'user', content: question),
    ];
  }
}
