"""
Arabic Buddy - "My ... story": 5 short, fully vowelled sentences built from the child's choices.
Uses only reviewed words: arabic_cache.json (+ 'adjectives'), adjectives.json, colours.json.

In the app: make_story(item, colour="red", size="big", fun="happy")
Run this file to write story_review.csv (2 sample stories per word).
"""
import json, random, csv
from arabic_forms import noun, adj as adj_ar
from phon import noun_ph, adj_ph, cap
from arabic_forms import waqf_ar, waqf_ph

ITEMS = json.load(open("arabic_cache.json", encoding="utf-8"))
ADJ = {a["id"]: a for a in json.load(open("adjectives.json", encoding="utf-8"))}
COL = {c["id"]: c for c in json.load(open("colours.json", encoding="utf-8"))}
LIKE_CATEGORIES = {"toys", "food"}
LIKE_IDS = {"sofa", "bed", "dress", "shirt", "shoe", "bag", "picture", "blanket", "pillow"}

def pick(entry, g):
    return (entry["m"], entry["ph_m"]) if g == "M" else (entry["f"], entry["ph_f"])

def noun_en(item):
    return (item.get("en_def") or "the " + item["english_word"].lower())[4:]

def english_np(item, a):
    n = noun_en(item); indef = item.get("en_indef") or ""
    if item.get("en_plural"):
        return f"a pair of {a} {n}" if indef.startswith("a pair of") else f"{a} {n}"
    if indef and not indef.startswith(("a ", "an ")):
        return f"{a} {n}"
    return ("an " if a[0] in "aeiou" else "a ") + f"{a} {n}"

IMAGE_RULES = ("Change only that. Keep everything else exactly as it is: the same {obj}, the changes from earlier pages, "
               "the same cute 3D cartoon sticker style and the plain white background. No text, no letters, no numbers, no people.")

def image_prompt(cue, obj):
    """Edit instruction for Muse Image: applied to the PREVIOUS page's picture (page 1 edits the word's sticker)."""
    if not cue:
        return None
    return "Edit this picture: " + cue.format(obj=obj) + ". " + IMAGE_RULES.format(obj=obj)

def make_story(item, colour=None, size=None, fun=None, rng=None):
    rng = rng or random.Random()
    g = item["gender"]; dip = lambda e: e.get("diptote", False)
    be = "are" if item.get("en_plural") else "is"
    The = "The " + noun_en(item)
    if size and not item.get("size_choice", True):
        size = None
    avoid = ({"big", "small"} if size else set()) | ({"colourful"} if colour else set())
    facts = [a for a in item.get("adjectives", []) if a not in avoid] or ["beautiful"]
    rng.shuffle(facts)
    if len(facts) == 1: facts = facts * 2
    lines = []
    obj = noun_en(item)
    def add(ar, ph, en, hl, cue=None):
        lines.append({"arabic": ar, "audio_text": waqf_ar(ar), "phonetic": waqf_ph(ph), "english": en, "highlight": hl,
                      "image_prompt": image_prompt(cue, obj)})

    this = ("هَذَا", "Hadha") if g == "M" else ("هَذِهِ", "Hadhihi")
    # 1  هَذَا بَابٌ جَدِيدٌ
    a, aph = pick(ADJ[facts[0]], g); A = adj_ar(a, "nom", False)
    en1 = (f"These are {english_np(item, ADJ[facts[0]]['en'])}." if item.get("en_plural") and not (item.get("en_indef") or "").startswith("a pair")
           else f"This is {english_np(item, ADJ[facts[0]]['en'])}.")
    add(f"{this[0]} {noun(item,'nom',False)} {A}", f"{this[1]} {noun_ph(item,'nom',False)} {adj_ph(aph,a,'nom',False)}", en1, [A], ADJ[facts[0]]["visual_cue"])
    D, Dp = noun(item, "nom", True), cap(noun_ph(item, "nom", True))
    # 2  الْبَابُ أَحْمَرُ
    if colour:
        c, cph = pick(COL[colour], g); C = adj_ar(c, "nom", False, dip(COL[colour]))
        add(f"{D} {C}", f"{Dp} {adj_ph(cph,c,'nom',False,dip(COL[colour]))}", f"{The} {be} {COL[colour]['en']}.", [C], COL[colour]["visual_cue"])
    # 3  الْبَابُ كَبِيرٌ  (or a third fact for liquids)
    third = size or next((x for x in item.get("adjectives", []) if x not in facts[:2] and x not in avoid), None)
    if third:
        s, sph = pick(ADJ[third], g); S = adj_ar(s, "nom", False)
        add(f"{D} {S}", f"{Dp} {adj_ph(sph,s,'nom',False)}", f"{The} {be} {ADJ[third]['en']}.", [S], ADJ[third]["visual_cue"])
    # 4  عِنْدِي بَابٌ نَظِيفٌ
    b, bph = pick(ADJ[facts[1]], g); B = adj_ar(b, "nom", False)
    add(f"عِنْدِي {noun(item,'nom',False)} {B}", f"'Indi {noun_ph(item,'nom',False)} {adj_ph(bph,b,'nom',False)}",
        f"I have {english_np(item, ADJ[facts[1]]['en'])}.", [B], ADJ[facts[1]]["visual_cue"])
    # 5  أَنَا أُحِبُّ الْبَابَ السَّعِيدَ  /  أَيْنَ الْبَابُ السَّعِيدُ؟
    last = ADJ[fun] if fun else (COL[colour] if colour else ADJ[facts[0]])
    l, lph = pick(last, g)
    if item["category"] in LIKE_CATEGORIES or item["id"] in LIKE_IDS:
        L = adj_ar(l, "acc", True)
        add(f"أَنَا أُحِبُّ {noun(item,'acc',True)} {L}", f"Ana uhibbu {noun_ph(item,'acc',True)} {adj_ph(lph,l,'acc',True)}",
            f"I like the {last['en']} {noun_en(item)}.", [L], last["visual_cue"] if last is not COL.get(colour) else None)
    else:
        L = adj_ar(l, "nom", True)
        add(f"أَيْنَ {D} {L}؟", f"Ayna {noun_ph(item,'nom',True)} {adj_ph(lph,l,'nom',True)}?",
            f"Where {be} the {last['en']} {noun_en(item)}?", [L], last["visual_cue"] if last is not COL.get(colour) else None)
    return lines[:5]

if __name__ == "__main__":
    rng = random.Random(7)
    with open("story_review.csv", "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f); w.writerow(["word", "choices", "#", "arabic", "phonetic", "english", "OK? (Y/N)", "correction", "picture"])
        for it in ITEMS:
            for _ in range(2):
                col = rng.choice(list(COL)); size = rng.choice(["big", "small"]); fun = rng.choice([None, "happy", "funny"])
                for n, ln in enumerate(make_story(it, col, size, fun, rng), 1):
                    w.writerow([it["english_word"], f"{col}/{size}/{fun or '-'}", n, ln["arabic"], ln["phonetic"], ln["english"], "", "", ln["image_prompt"] or "(same picture as before)"])
    print("wrote story_review.csv")
