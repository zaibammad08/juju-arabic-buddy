"""Phonetic spelling with case endings (shared by build_sentences.py and story.py)."""
import re
from arabic_forms import ph_case
SUN = set("تثدذرزسشصضطظلن")
TASH = re.compile(r"[\u064B-\u0652\u0670]")
DIGRAPHS = ("sh", "th", "dh", "kh", "gh")
V = {"nom": "u", "acc": "a", "gen": "i"}

def al_ph(ph, arabic):
    low = ph[0].lower() + ph[1:]
    if TASH.sub("", arabic)[0] in SUN:
        cons = low[:2] if low[:2] in DIGRAPHS else low[0]
        return f"a{cons}-{low}"
    return f"al-{low}"

def noun_ph(item, case, definite):
    if item.get("idafa_tail"):
        head, tail = item["head_ph"], item["tail_ph"]
        return f"{head}{V[case]} " + (f"al-{tail}i" if definite else f"{tail}in")
    base = item["phonetic"][0].lower() + item["phonetic"][1:]
    if definite:
        base = al_ph(item["phonetic"], item["arabic_word"])
    return ph_case(base, item["arabic_word"], case, definite, kind=item.get("form"))

def adj_ph(ph, arabic, case, definite, diptote=False):
    base = al_ph(ph, arabic) if definite else ph
    return ph_case(base, arabic, case, definite, diptote=diptote)

def with_bi(p):
    return "bi" + p[1:] if p.startswith("a") else "bi " + p

cap = lambda s: s[0].upper() + s[1:]
