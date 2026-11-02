"""
Arabic Buddy - full vowel marking (tashkeel) with case endings, done by rules.
Used by build_sentences.py and story.py.

Cases used in our sentences:
  nom = marfu' (subject / after هذا, عندي, أين, predicate adjective)
  acc = mansub (object of a verb: أرى، أحب، آكل…)
  gen = majrur (after بِـ، عَلَى)
"""
import re

FATHA, DAMMA, KASRA, SUKUN, SHADDA = "\u064E", "\u064F", "\u0650", "\u0652", "\u0651"
TANWEEN = {"nom": "\u064C", "acc": "\u064B", "gen": "\u064D"}   # ٌ ً ٍ
VOWEL = {"nom": DAMMA, "acc": FATHA, "gen": KASRA}
HARAKAT = set("\u064B\u064C\u064D\u064E\u064F\u0650\u0652")
MARKS = HARAKAT | {SHADDA, "\u0670"}
SUN = set("تثدذرزسشصضطظلن")
TASH = re.compile("[\u064B-\u0652\u0670]")

def _clusters(word):
    """split into [letter, marks] pairs"""
    out = []
    for ch in word:
        if ch in MARKS and out:
            out[-1][1] += ch
        else:
            out.append([ch, ""])
    return out

def _join(cl): return "".join(c + m for c, m in cl)

def vocalize(word):
    """Fill in obvious missing marks inside a word (not the case ending):
       fatha before long alif, fatha on a bare shadda, damma before long waw, kasra before long yaa."""
    parts = []
    for w in word.split(" "):
        cl = _clusters(w)
        for k in range(len(cl) - 1):
            ch, m = cl[k]; nxt, nm = cl[k + 1]
            has_vowel = any(x in HARAKAT for x in m)
            if ch in "اأإآءى" or (k == 0 and ch == "ا"):
                continue
            if nxt == "ا" and not has_vowel:
                cl[k][1] = m + FATHA
            elif nxt == "و" and not nm and not has_vowel and k + 1 < len(cl) - 0:
                cl[k][1] = m + DAMMA
            elif nxt == "ي" and not nm and not has_vowel and SHADDA not in nm:
                cl[k][1] = m + KASRA
        # bare shadda not on the last letter -> shadda + fatha
        for k in range(len(cl) - 1):
            m = cl[k][1]
            if SHADDA in m and not any(x in HARAKAT for x in m):
                cl[k][1] = SHADDA + FATHA
        parts.append(_join(cl))
    return " ".join(parts)

def _strip_end(word):
    cl = _clusters(word)
    cl[-1][1] = "".join(x for x in cl[-1][1] if x == SHADDA)   # keep shadda, drop vowel
    return cl

def end_case(word, case, definite, diptote=False, kind=None):
    """Add the case ending to the LAST word."""
    if kind == "indeclinable":
        return word
    if kind == "maqsur":            # مُرَبَّى: no visible ending; indefinite = مُرَبًّى
        return word if definite else word.replace(SHADDA + FATHA + "ى", SHADDA + "\u064B" + "ى")
    cl = _strip_end(word)
    if definite or diptote:
        mark = VOWEL[case] if not (diptote and not definite and case == "gen") else FATHA
    else:
        mark = TANWEEN[case]
    cl[-1][1] = cl[-1][1] + mark
    return _join(cl)

def al(word):
    """add the article: الْ + moon letter, الـ + shadda on sun letter"""
    cl = _clusters(word)
    if cl[0][0] in SUN:
        vowel = "".join(x for x in cl[0][1] if x in HARAKAT)
        cl[0][1] = SHADDA + vowel
        return "ال" + _join(cl)
    return "ال" + SUKUN + word

def noun(item, case, definite):
    """Fully vowelled noun phrase for a word in arabic_cache.json."""
    w = item["arabic_word"]
    kind = item.get("form")
    tail = item.get("idafa_tail")           # فُرْشَاة أَسْنَان
    if tail:
        head = w.split(" ")[0]
        head = end_case(head, case, True)   # first part of an idafa: never tanween
        t = al(tail) if definite else tail
        return head + " " + end_case(t, "gen", definite)
    base = al(w) if definite else w
    return end_case(base, case, definite, kind=kind)

def adj(form, case, definite, diptote=False):
    base = al(form) if definite else form
    return end_case(base, case, definite, diptote=diptote)

# ---------- phonetic with endings ----------
END_PH = {"nom": "u", "acc": "a", "gen": "i"}
def ph_case(ph, arabic, case, definite, diptote=False, kind=None):
    if kind in ("indeclinable", "maqsur"):
        return ph + ("n" if kind == "maqsur" and not definite else "")
    base = TASH.sub("", arabic).split(" ")[-1]
    v = END_PH[case] if not (diptote and not definite and case == "gen") else "a"
    if base.endswith("ة"):
        ph = ph + "t"
    elif arabic.rstrip().endswith("ي" + SHADDA) or arabic.rstrip().endswith("يّ"):
        if ph.endswith("i") and not ph.endswith("iyy"):
            ph = ph[:-1] + "iyy"              # kursi -> kursiyyun
    return ph + v + ("n" if not definite and not diptote else "")


# ---------- waqf: how the LAST word is said when you stop ----------
import re as _re
def waqf_ar(sentence):
    """Text for the audio voice: same sentence, but the last word ends in a stop (sukun),
    e.g. أَيْنَ الْبَابُ؟ -> أَيْنَ الْبَابْ؟ . Display text keeps the full ending."""
    m = _re.match(r"^(.*?)([^\s؟.!]+)([؟.!]*)$", sentence.strip())
    if not m:
        return sentence
    head, last, punct = m.groups()
    cl = _clusters(last)
    end = cl[-1]
    if end[0] == "ى":                     # مُرَبًّى -> مُرَبَّى
        if len(cl) > 1:
            cl[-2][1] = cl[-2][1].replace("\u064B", FATHA)
    elif end[0] in "اوي" and not end[1]:
        pass                              # long vowel letter (يُويُو): nothing to add
    else:
        keep = "".join(x for x in end[1] if x == SHADDA)
        end[1] = keep                     # drop the case ending; NO sukun added (Azure shortens long vowels when it sees sukun)
    return (head + _join(cl) + punct).replace(SUKUN, "")   # audio text: no sukun signs at all (tested 25 Oct)

def waqf_ph(ph):
    """Phonetic of the spoken (stopped) sentence: drop the case ending of the last word."""
    m = _re.match(r"^(.*?)(\S+?)([?.!]*)$", ph.strip())
    head, last, punct = m.groups()
    for pat, rep in ((r"iyy(un|u|a|i)$", "i"), (r"t(un|u|a|i|an|in)$", ""), (r"an$", "a"),
                     (r"(?<=[^aeiou'])(un|in|u|a|i)$", ""), (r"(?<=')(un|in|u|a|i)$", "")):
        if _re.search(pat, last):
            last = _re.sub(pat, rep, last)
            break
    return head + last + punct
