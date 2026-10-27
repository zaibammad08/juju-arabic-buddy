// Arabic Buddy – Dart port of arabic_forms.py + phon.py + story.py.
// Same rules, same output, so the app and the Python review sheets agree.
//
// Cases:  nom = marfu' (after هَذَا، عِنْدِي، أَيْنَ, predicate adjective)
//         acc = mansub (object of a verb: أُحِبُّ…)
//         gen = majrur (after بِـ، عَلَى)
//
// Display text keeps every mark. Speech text: use ArabicForms.forSpeech().

import 'dart:math';

import 'models.dart';

enum Case { nom, acc, gen }

class _Cl {
  _Cl(this.ch, this.m);
  String ch; // base letter
  String m; // marks after it
}

class ArabicForms {
  ArabicForms._();

  static const fatha = '\u064E', damma = '\u064F', kasra = '\u0650';
  static const sukun = '\u0652', shadda = '\u0651';
  static const _tanween = {
    Case.nom: '\u064C',
    Case.acc: '\u064B',
    Case.gen: '\u064D',
  };
  static const _vowel = {Case.nom: damma, Case.acc: fatha, Case.gen: kasra};
  static const _harakat = '\u064B\u064C\u064D\u064E\u064F\u0650\u0652';
  static const _marks = '$_harakat$shadda\u0670';
  static const sunLetters = 'تثدذرزسشصضطظلن';
  static final _tash = RegExp('[\u064B-\u0652\u0670]');

  static bool _isMark(String c) => _marks.contains(c);
  static bool _isHaraka(String c) => _harakat.contains(c);
  static bool _hasHaraka(String m) => m.split('').any(_isHaraka);

  /// Remove all vowel marks (only for comparing speech – never for display).
  static String strip(String s) => s.replaceAll(_tash, '');

  /// For comparing speech: no marks, lower-case, أ/إ/آ→ا, ة→ه, ى→ي, no punctuation.
  static String normalise(String s) => strip(s)
      .toLowerCase()
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('\u0640', '') // tatweel
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Levenshtein ratio 0..1 on normalised text (1 = identical).
  static double similarity(String a, String b) {
    final x = normalise(a).replaceAll(' ', ''),
        y = normalise(b).replaceAll(' ', '');
    if (x.isEmpty && y.isEmpty) return 1;
    if (x.isEmpty || y.isEmpty) return 0;
    var prev = List<int>.generate(y.length + 1, (j) => j);
    for (var i = 1; i <= x.length; i++) {
      final cur = List<int>.filled(y.length + 1, 0)..[0] = i;
      for (var j = 1; j <= y.length; j++) {
        final cost = x[i - 1] == y[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce(min);
      }
      prev = cur;
    }
    final longest = x.length > y.length ? x.length : y.length;
    return 1 - prev[y.length] / longest;
  }

  /// Text for live TTS: no sukun (sukun made Azure cut words short, 25 Oct).
  static String forSpeech(String audioText) => audioText.replaceAll(sukun, '');

  static List<_Cl> _clusters(String word) {
    final out = <_Cl>[];
    for (final ch in word.split('')) {
      if (_isMark(ch) && out.isNotEmpty) {
        out.last.m += ch;
      } else {
        out.add(_Cl(ch, ''));
      }
    }
    return out;
  }

  static String _join(List<_Cl> cl) => cl.map((c) => c.ch + c.m).join();

  /// Fill obvious missing marks inside a word (not the case ending).
  static String vocalize(String word) {
    final parts = <String>[];
    for (final w in word.split(' ')) {
      final cl = _clusters(w);
      for (var k = 0; k < cl.length - 1; k++) {
        final ch = cl[k].ch, m = cl[k].m;
        final nxt = cl[k + 1].ch, nm = cl[k + 1].m;
        final hasVowel = _hasHaraka(m);
        if ('اأإآءى'.contains(ch) || (k == 0 && ch == 'ا')) continue;
        if (nxt == 'ا' && !hasVowel) {
          cl[k].m = m + fatha;
        } else if (nxt == 'و' && nm.isEmpty && !hasVowel) {
          cl[k].m = m + damma;
        } else if (nxt == 'ي' &&
            nm.isEmpty &&
            !hasVowel &&
            !nm.contains(shadda)) {
          cl[k].m = m + kasra;
        }
      }
      // bare shadda not on the last letter -> shadda + fatha
      for (var k = 0; k < cl.length - 1; k++) {
        final m = cl[k].m;
        if (m.contains(shadda) && !_hasHaraka(m)) cl[k].m = shadda + fatha;
      }
      parts.add(_join(cl));
    }
    return parts.join(' ');
  }

  static List<_Cl> _stripEnd(String word) {
    final cl = _clusters(word);
    cl.last.m = cl.last.m.split('').where((x) => x == shadda).join();
    return cl;
  }

  /// Add the case ending to the LAST word.
  static String endCase(
    String word,
    Case c,
    bool definite, {
    bool diptote = false,
    String? kind,
  }) {
    if (kind == 'indeclinable') return word;
    if (kind == 'maqsur') {
      // مُرَبَّى: no visible ending; indefinite = مُرَبًّى
      return definite
          ? word
          : word.replaceAll('$shadda$fathaى', '$shadda\u064Bى');
    }
    final cl = _stripEnd(word);
    final String mark;
    if (definite || diptote) {
      mark = (diptote && !definite && c == Case.gen) ? fatha : _vowel[c]!;
    } else {
      mark = _tanween[c]!;
    }
    cl.last.m = cl.last.m + mark;
    return _join(cl);
  }

  /// Add the article: الْ + moon letter, الـ + shadda on a sun letter.
  static String al(String word) {
    final cl = _clusters(word);
    if (sunLetters.contains(cl.first.ch)) {
      final vowel = cl.first.m.split('').where(_isHaraka).join();
      cl.first.m = shadda + vowel;
      return 'ال${_join(cl)}';
    }
    return 'ال$sukun$word';
  }

  /// Fully vowelled noun phrase for a hunt word.
  static String noun(HuntWord item, Case c, bool definite) {
    final w = item.arabicWord;
    final tail = item.idafaTail; // فُرْشَاة أَسْنَان
    if (tail != null && tail.isNotEmpty) {
      final head = endCase(
        w.split(' ').first,
        c,
        true,
      ); // idafa head: never tanween
      final t = definite ? al(tail) : tail;
      return '$head ${endCase(t, Case.gen, definite)}';
    }
    final base = definite ? al(w) : w;
    return endCase(base, c, definite, kind: item.form);
  }

  static String adj(
    String form,
    Case c,
    bool definite, {
    bool diptote = false,
  }) {
    final base = definite ? al(form) : form;
    return endCase(base, c, definite, diptote: diptote);
  }

  // ---------- phonetics with endings ----------
  static const _endPh = {Case.nom: 'u', Case.acc: 'a', Case.gen: 'i'};

  static String phCase(
    String ph,
    String arabic,
    Case c,
    bool definite, {
    bool diptote = false,
    String? kind,
  }) {
    if (kind == 'indeclinable' || kind == 'maqsur') {
      return ph + (kind == 'maqsur' && !definite ? 'n' : '');
    }
    final base = strip(arabic).split(' ').last;
    final v = (diptote && !definite && c == Case.gen) ? 'a' : _endPh[c]!;
    var p = ph;
    if (base.endsWith('ة')) {
      p = '${p}t';
    } else if (arabic.trimRight().endsWith('ي$shadda')) {
      if (p.endsWith('i') && !p.endsWith('iyy')) {
        p = '${p.substring(0, p.length - 1)}iyy'; // kursi -> kursiyyun
      }
    }
    return p + v + (!definite && !diptote ? 'n' : '');
  }

  // ---------- waqf: how the LAST word is said when you stop ----------
  static final _waqfArRe = RegExp(r'^(.*?)([^\s؟.!]+)([؟.!]*)$');

  /// أَيْنَ الْبَابُ؟ -> أَيْنَ الْبَابْ؟  (then forSpeech() drops the sukun for TTS)
  static String waqfAr(String sentence) {
    final m = _waqfArRe.firstMatch(sentence.trim());
    if (m == null) return sentence;
    final head = m.group(1)!, last = m.group(2)!, punct = m.group(3)!;
    final cl = _clusters(last);
    final end = cl.last;
    if (end.ch == 'ى') {
      // مُرَبًّى -> مُرَبَّى
      if (cl.length > 1) {
        cl[cl.length - 2].m = cl[cl.length - 2].m.replaceAll('\u064B', fatha);
      }
    } else if ('اوي'.contains(end.ch) && end.m.isEmpty) {
      // long vowel letter (يُويُو): nothing to add
    } else {
      final keep = end.m.split('').where((x) => x == shadda).join();
      end.m = keep + (keep.isEmpty ? sukun : '');
    }
    return head + _join(cl) + punct;
  }

  static final _waqfPhRe = RegExp(r'^(.*?)(\S+?)([?.!]*)$');
  static final _waqfPhRules = <(RegExp, String)>[
    (RegExp(r'iyy(un|u|a|i)$'), 'i'),
    (RegExp(r't(un|u|a|i|an|in)$'), ''),
    (RegExp(r'an$'), 'a'),
    (RegExp(r"(?<=[^aeiou'])(un|in|u|a|i)$"), ''),
    (RegExp(r"(?<=')(un|in|u|a|i)$"), ''),
  ];

  /// Phonetic of the spoken (stopped) sentence: drop the last word's ending.
  static String waqfPh(String ph) {
    final m = _waqfPhRe.firstMatch(ph.trim());
    if (m == null) return ph;
    final head = m.group(1)!, punct = m.group(3)!;
    var last = m.group(2)!;
    for (final (re, rep) in _waqfPhRules) {
      if (re.hasMatch(last)) {
        last = last.replaceFirst(re, rep);
        break;
      }
    }
    return head + last + punct;
  }

  // ---------- phon.py ----------
  static const _digraphs = ['sh', 'th', 'dh', 'kh', 'gh'];
  static const _v = {Case.nom: 'u', Case.acc: 'a', Case.gen: 'i'};

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
  static String cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String alPh(String ph, String arabic) {
    final low = _lowerFirst(ph);
    final first = strip(arabic);
    if (first.isNotEmpty && sunLetters.contains(first[0])) {
      final two = low.length >= 2 ? low.substring(0, 2) : low;
      final cons = _digraphs.contains(two) ? two : low[0];
      return 'a$cons-$low';
    }
    return 'al-$low';
  }

  static String nounPh(HuntWord item, Case c, bool definite) {
    if (item.idafaTail != null && item.idafaTail!.isNotEmpty) {
      final head = item.headPh, tail = item.tailPh;
      return '$head${_v[c]} ${definite ? 'al-${tail}i' : '${tail}in'}';
    }
    final base = definite
        ? alPh(item.phonetic, item.arabicWord)
        : _lowerFirst(item.phonetic);
    return phCase(base, item.arabicWord, c, definite, kind: item.form);
  }

  static String adjPh(
    String ph,
    String arabic,
    Case c,
    bool definite, {
    bool diptote = false,
  }) {
    final base = definite ? alPh(ph, arabic) : ph;
    return phCase(base, arabic, c, definite, diptote: diptote);
  }

  static String withBi(String p) =>
      p.startsWith('a') ? 'bi${p.substring(1)}' : 'bi $p';
}

// ---------------------------------------------------------------------------
// story.py – 5 short sentences built from the child's choices.
// ---------------------------------------------------------------------------
class StoryBuilder {
  StoryBuilder({required this.adjectives, required this.colours});

  final Map<String, Adjective> adjectives;
  final Map<String, ArabicColour> colours;

  static const likeCategories = {'toys', 'food'};
  static const likeIds = {
    'sofa',
    'bed',
    'dress',
    'shirt',
    'shoe',
    'bag',
    'picture',
    'blanket',
    'pillow',
  };

  static const _imageRules =
      'Change only that. Keep everything else exactly as it is: the same {obj}, '
      'the changes from earlier pages, the same cute 3D cartoon sticker style and '
      'the plain white background. No text, no letters, no numbers, no people.';

  static String nounEn(HuntWord item) {
    final d = item.enDef.isNotEmpty
        ? item.enDef
        : 'the ${item.englishWord.toLowerCase()}';
    return d.length > 4 ? d.substring(4) : d;
  }

  static String englishNp(HuntWord item, String a) {
    final n = nounEn(item);
    final indef = item.enIndef;
    if (item.enPlural) {
      return indef.startsWith('a pair of') ? 'a pair of $a $n' : '$a $n';
    }
    if (indef.isNotEmpty &&
        !(indef.startsWith('a ') || indef.startsWith('an '))) {
      return '$a $n';
    }
    return '${'aeiou'.contains(a[0]) ? 'an ' : 'a '}$a $n';
  }

  /// Muse Image edit instruction for this page (applied to the previous page's picture).
  static String? imagePrompt(String? cue, String obj) {
    if (cue == null || cue.isEmpty) return null;
    return 'Edit this picture: ${cue.replaceAll('{obj}', obj)}. '
        '${_imageRules.replaceAll('{obj}', obj)}';
  }

  Story make(
    HuntWord item, {
    String? colour,
    String? size,
    String? fun,
    Random? rng,
  }) {
    rng ??= Random();
    const nom = Case.nom, acc = Case.acc;
    final g = item.gender;
    final be = item.enPlural ? 'are' : 'is';
    final the = 'The ${nounEn(item)}';
    final obj = nounEn(item);
    final col = colour == null ? null : colours[colour];
    if (colour != null && col == null) colour = null;
    if (size != null && !item.sizeChoice) size = null;

    final avoid = <String>{
      if (size != null) ...['big', 'small'],
      if (colour != null) 'colourful',
    };
    var facts = item.adjectives
        .where((a) => !avoid.contains(a) && adjectives.containsKey(a))
        .toList();
    if (facts.isEmpty) facts = ['beautiful'];
    facts.shuffle(rng);
    if (facts.length == 1) facts = [facts[0], facts[0]];

    final lines = <SentenceLine>[];
    void add(String ar, String ph, String en, List<String> hl, String? cue) {
      lines.add(
        SentenceLine({
          'arabic': ar,
          'audio_text': ArabicForms.waqfAr(ar),
          'phonetic': ArabicForms.waqfPh(ph),
          'english': en,
          'highlight': hl,
          'image_prompt': imagePrompt(cue, obj),
        }),
      );
    }

    final thisAr = g == 'M' ? 'هَذَا' : 'هَذِهِ';
    final thisPh = g == 'M' ? 'Hadha' : 'Hadhihi';

    // 1  هَذَا بَابٌ جَدِيدٌ
    final adj0 = adjectives[facts[0]]!;
    final (a, aph) = adj0.forGender(g);
    final aAr = ArabicForms.adj(a, nom, false);
    final en1 = item.enPlural && !item.enIndef.startsWith('a pair')
        ? 'These are ${englishNp(item, adj0.en)}.'
        : 'This is ${englishNp(item, adj0.en)}.';
    add(
      '$thisAr ${ArabicForms.noun(item, nom, false)} $aAr',
      '$thisPh ${ArabicForms.nounPh(item, nom, false)} ${ArabicForms.adjPh(aph, a, nom, false)}',
      en1,
      [aAr],
      adj0.visualCue,
    );

    final dAr = ArabicForms.noun(item, nom, true);
    final dPh = ArabicForms.cap(ArabicForms.nounPh(item, nom, true));

    // 2  الْبَابُ أَحْمَرُ
    if (col != null) {
      final (c, cph) = col.forGender(g);
      final cAr = ArabicForms.adj(c, nom, false, diptote: col.diptote);
      add(
        '$dAr $cAr',
        '$dPh ${ArabicForms.adjPh(cph, c, nom, false, diptote: col.diptote)}',
        '$the $be ${col.en}.',
        [cAr],
        col.visualCue,
      );
    }

    // 3  الْبَابُ كَبِيرٌ  (or a third fact for liquids)
    String? third = size;
    if (third == null) {
      for (final x in item.adjectives) {
        if (!facts.take(2).contains(x) &&
            !avoid.contains(x) &&
            adjectives.containsKey(x)) {
          third = x;
          break;
        }
      }
    }
    final adj3 = third == null ? null : adjectives[third];
    if (adj3 != null) {
      final (s, sph) = adj3.forGender(g);
      final sAr = ArabicForms.adj(s, nom, false);
      add(
        '$dAr $sAr',
        '$dPh ${ArabicForms.adjPh(sph, s, nom, false)}',
        '$the $be ${adj3.en}.',
        [sAr],
        adj3.visualCue,
      );
    }

    // 4  عِنْدِي بَابٌ نَظِيفٌ
    final adj1 = adjectives[facts[1]]!;
    final (b, bph) = adj1.forGender(g);
    final bAr = ArabicForms.adj(b, nom, false);
    add(
      'عِنْدِي ${ArabicForms.noun(item, nom, false)} $bAr',
      "'Indi ${ArabicForms.nounPh(item, nom, false)} ${ArabicForms.adjPh(bph, b, nom, false)}",
      'I have ${englishNp(item, adj1.en)}.',
      [bAr],
      adj1.visualCue,
    );

    // 5  أَنَا أُحِبُّ الْبَابَ السَّعِيدَ  /  أَيْنَ الْبَابُ السَّعِيدُ؟
    final funAdj = fun == null ? null : adjectives[fun];
    final GenderedWord last = funAdj ?? col ?? adj0;
    final lastIsColour = identical(last, col);
    final (l, lph) = last.forGender(g);
    final cue = lastIsColour ? null : last.visualCue;
    if (likeCategories.contains(item.category) || likeIds.contains(item.id)) {
      final lAr = ArabicForms.adj(l, acc, true);
      add(
        'أَنَا أُحِبُّ ${ArabicForms.noun(item, acc, true)} $lAr',
        'Ana uhibbu ${ArabicForms.nounPh(item, acc, true)} ${ArabicForms.adjPh(lph, l, acc, true)}',
        'I like the ${last.en} ${nounEn(item)}.',
        [lAr],
        cue,
      );
    } else {
      final lAr = ArabicForms.adj(l, nom, true);
      add(
        'أَيْنَ $dAr $lAr؟',
        'Ayna ${ArabicForms.nounPh(item, nom, true)} ${ArabicForms.adjPh(lph, l, nom, true)}?',
        'Where $be the ${last.en} ${nounEn(item)}?',
        [lAr],
        cue,
      );
    }

    return Story(
      wordId: item.id,
      colour: colour,
      size: size,
      fun: fun,
      lines: lines.take(5).toList(),
    );
  }
}
