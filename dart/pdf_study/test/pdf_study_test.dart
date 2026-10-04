import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf_study/src/ai/ai.dart';
import 'package:pdf_study/src/ai/context.dart';
import 'package:pdf_study/src/models.dart';
import 'package:pdf_study/src/srs.dart';
import 'package:pdf_study/src/ui/flashcard_panel.dart';

void main() {
  group('SM-2', () {
    test('首次记得 → 1 天，二次 → 6 天，之后按 ease 增长', () {
      final c = Flashcard(id: 'a', front: 'f', back: 'b');
      final t0 = DateTime(2026, 1, 1);
      Srs.review(c, Srs.gradeGood, now: t0);
      expect(c.intervalDays, 1);
      expect(c.due, t0.add(const Duration(days: 1)));
      Srs.review(c, Srs.gradeGood, now: t0.add(const Duration(days: 1)));
      expect(c.intervalDays, 6);
      Srs.review(c, Srs.gradeGood, now: t0.add(const Duration(days: 7)));
      expect(c.intervalDays, (6 * c.ease).round());
    });

    test('重来会清空间隔并进入 10 分钟后复习', () {
      final c = Flashcard(id: 'a', front: 'f', back: 'b');
      final t0 = DateTime(2026, 1, 1);
      Srs.review(c, Srs.gradeGood, now: t0);
      Srs.review(c, Srs.gradeGood, now: t0);
      Srs.review(c, Srs.gradeAgain, now: t0);
      expect(c.reps, 0);
      expect(c.lapses, 1);
      expect(c.intervalDays, 0);
      expect(c.due.difference(t0).inMinutes, 10);
    });

    test('ease 不低于 1.3，困难/简单调整幅度不同', () {
      final c = Flashcard(id: 'a', front: 'f', back: 'b');
      for (var i = 0; i < 10; i++) {
        Srs.review(
          c,
          Srs.gradeHard,
          now: DateTime(2026, 1, 1).add(Duration(days: i * 40)),
        );
      }
      expect(c.ease, greaterThanOrEqualTo(1.3));
      final d = Flashcard(id: 'b', front: 'f', back: 'b');
      final e = Flashcard(id: 'c', front: 'f', back: 'b');
      for (var i = 0; i < 5; i++) {
        Srs.review(
          d,
          Srs.gradeEasy,
          now: DateTime(2026, 1, 1).add(Duration(days: i * 30)),
        );
        Srs.review(
          e,
          Srs.gradeHard,
          now: DateTime(2026, 1, 1).add(Duration(days: i * 30)),
        );
      }
      expect(d.ease, greaterThan(e.ease));
    });
  });

  group('SSE 解析', () {
    test('parseOpenAiSseLine 提取 delta.content', () {
      expect(
        parseOpenAiSseLine('{"choices":[{"delta":{"content":"你好"}}]}'),
        '你好',
      );
      expect(parseOpenAiSseLine('[DONE]'), isNull);
      expect(parseOpenAiSseLine(''), isNull);
      expect(parseOpenAiSseLine('not json'), isNull);
      expect(parseOpenAiSseLine('{"choices":[]}'), isNull);
    });

    test('sseDataStream 按行拆出 data 载荷', () async {
      final bytes = utf8.encode(
        'event: msg\ndata: {"a":1}\n\ndata: line2\nretry: 3\ndata: [DONE]\n',
      );
      final out = await sseDataStream(Stream.value(bytes)).toList();
      expect(out, ['{"a":1}', 'line2', '[DONE]']);
    });

    test('sseDataStream 处理跨 chunk 的行', () async {
      final parts = [
        'data: he',
        'llo\nda',
        'ta: world\n',
      ].map((s) => utf8.encode(s)).toList();
      final out = await sseDataStream(Stream.fromIterable(parts)).toList();
      expect(out, ['hello', 'world']);
    });
  });

  group('卡片 JSON 解析', () {
    test('标准结构', () {
      final cards = parseCardsJson(
        '{"cards":[{"front":"Q","back":"A","page":3}]}',
      );
      expect(cards.length, 1);
      expect(cards.first['front'], 'Q');
      expect(cards.first['page'], 3);
    });

    test('容忍代码块包裹', () {
      final cards = parseCardsJson(
        '前言\n```json\n{"cards":[{"front":"Q","back":"A"}]}\n```\n后记',
      );
      expect(cards.length, 1);
    });

    test('容忍裸数组', () {
      final cards = parseCardsJson('[{"front":"Q","back":"A"}]');
      expect(cards.length, 1);
    });

    test('垃圾输入返回空', () {
      expect(parseCardsJson('完全不是 JSON'), isEmpty);
      expect(parseCardsJson(''), isEmpty);
    });
  });

  group('章节范围', () {
    test('flattenOutline + chapterRangeFor', () {
      final outline = [
        const PdfOutlineNode(
          title: '第一章',
          dest: null,
          children: [
            PdfOutlineNode(
              title: '1.1',
              dest: PdfDest(3, PdfDestCommand.xyz, null),
              children: [],
            ),
          ],
        ),
        const PdfOutlineNode(
          title: '第二章',
          dest: PdfDest(10, PdfDestCommand.fit, null),
          children: [],
        ),
      ];
      final flat = flattenOutline(outline);
      expect(flat.length, 3);
      // 第5页 → 属于 1.1（第3页起），到第二章前（第10页）结束
      final r = chapterRangeFor(flat, 5, 20);
      expect(r.start, 3);
      expect(r.end, 10);
      expect(r.title, '1.1');
      // 最后章节到末尾
      final r2 = chapterRangeFor(flat, 15, 20);
      expect(r2.end, 21);
    });
  });

  group('模型序列化', () {
    test('Annotation 往返', () {
      final a = Annotation(
        id: 'x1',
        page: 3,
        rects: const [
          [10, 700, 200, 690],
          [10, 688, 180, 678],
        ],
        colorValue: 0xFFFFD54F,
        text: 'hello',
        note: 'note!',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = Annotation.fromJson(a.toJson());
      expect(b.id, a.id);
      expect(b.rects, a.rects);
      expect(b.colorValue, a.colorValue);
      expect(b.hasNote, isTrue);
    });

    test('Flashcard 往返', () {
      final c = Flashcard(
        id: 'c1',
        front: 'Q',
        back: 'A',
        page: 7,
        ease: 2.1,
        intervalDays: 3,
        reps: 2,
      );
      final d = Flashcard.fromJson(c.toJson());
      expect(d.front, 'Q');
      expect(d.ease, 2.1);
      expect(d.intervalDays, 3);
    });

    test('LibraryEntry 进度', () {
      final e = LibraryEntry(
        key: 'k',
        path: '/a.pdf',
        title: 't',
        pageCount: 10,
        lastPage: 5,
        lastOpened: DateTime.now(),
      );
      expect(e.progress, 0.5);
      final e2 = LibraryEntry.fromJson(e.toJson());
      expect(e2.key, 'k');
      expect(e2.progress, 0.5);
    });

    test('AiProviderConfig 往返', () {
      final c = AiProviderConfig(
        id: 'x',
        kind: AiProviderKind.devinApi,
        name: 'Dev',
        apiKey: 'k1',
        baseUrl: 'https://api.devin.ai',
      );
      final d = AiProviderConfig.fromJson(c.toJson());
      expect(d.kind, AiProviderKind.devinApi);
      expect(d.apiKey, 'k1');
    });
  });
}
