import 'models.dart';

/// SM-2 间隔重复打分（0-5）。
/// 复习界面四档：重来=1 / 困难=3 / 记得=4 / 简单=5。
class Srs {
  static const gradeAgain = 1;
  static const gradeHard = 3;
  static const gradeGood = 4;
  static const gradeEasy = 5;

  /// 更新卡片的 ease/interval/due/reps/lapses。
  static void review(Flashcard card, int grade, {DateTime? now}) {
    final t = now ?? DateTime.now();
    assert(grade >= 0 && grade <= 5);
    if (grade < 3) {
      card.lapses += 1;
      card.reps = 0;
      card.intervalDays = 0;
      card.due = t.add(const Duration(minutes: 10)); // 当次稍后重现
      return;
    }
    card.reps += 1;
    if (card.reps == 1) {
      card.intervalDays = 1;
    } else if (card.reps == 2) {
      card.intervalDays = grade == gradeHard ? 3 : 6;
    } else {
      card.intervalDays = (card.intervalDays * card.ease).round();
    }
    card.ease = (card.ease + (0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)))
        .clamp(1.3, 3.0);
    if (grade == gradeHard) {
      card.intervalDays = (card.intervalDays * 1.2).round().clamp(1, 1 << 20);
    }
    card.due = t.add(Duration(days: card.intervalDays));
  }

  /// 到期优先、其次新卡。
  static List<Flashcard> dueOrder(Iterable<Flashcard> cards, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final due = cards.where((c) => c.isDue(t)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return due;
  }
}
