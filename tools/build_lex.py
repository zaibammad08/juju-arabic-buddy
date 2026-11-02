"""
build_lex.py - the shared word library: one Arabic word (or sentence) = one mp3,
named after the word, reused by every lesson.

Run from the project root (E:\\juju-arabic-buddy):
    python tools/build_lex.py baa            # make the ب set
    python tools/build_lex.py baa --force    # re-make even if files exist
    python tools/build_lex.py baa --only bint buuma   # re-make just these
    python tools/build_lex.py meem                    # next letter (dal, seen, alif, all)
    python tools/build_lex.py juju_world              # colours + adjectives, both forms
    python tools/build_lex.py hunt                    # Treasure Hunt words
    python tools/build_lex.py hunt_sentences          # 5 sentences per hunt word
    python tools/build_lex.py story                   # every Story Maker line (~2,700)

Makes:
    assets/audio/lex/<name>.mp3       the audio
    assets/data/lex.json              Arabic -> file (merged, other letters kept)
    audio_test/lex_<set>.html         checklist: listen, tick wrong ones, copy

Rules (chosen by ear, 1 Nov):
    words      Fatima, rate -20%, pause at the end; final ة written as ه
    sentences  Fatima natural speed, pause at the end; final ة written as ه
    long sounds (بَا بِي بُو)  same as words
    lone short sounds (بَ بِ بُ) are NOT made - the app plays the example word
No sukun is ever sent to Azure (it made words sound clipped).

Key: AZURE_TTS_KEY / AZURE_TTS_REGION from the environment or secrets.json.
To add the next letter, add a list to SETS below and run it.
"""

import argparse
import html
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path.cwd()
LEX_DIR = ROOT / "assets" / "audio" / "lex"
LEX_JSON = ROOT / "assets" / "data" / "lex.json"
TEST_DIR = ROOT / "audio_test"

VOICE = "ar-AE-FatimaNeural"
WORD_RATE = "-20%"

# (file name, Arabic with full marks, kind)   kind: word | sentence
SETS = {
    "baa": [
        # vowel example words (these now carry the short sounds)
        ("bahr", "بَحْر", "word"),
        ("bint", "بِنْت", "word"),
        ("burtuqaal", "بُرْتُقَال", "word"),
        # long sounds
        ("baa", "بَا", "word"),
        ("bii", "بِي", "word"),
        ("buu", "بُو", "word"),
        # words with ب
        ("batta", "بَطَّة", "word"),
        ("baqara", "بَقَرَة", "word"),
        ("baab", "بَاب", "word"),
        ("bayd", "بَيْض", "word"),
        ("bayt", "بَيْت", "word"),
        ("bitriiq", "بِطْرِيق", "word"),
        ("buuma", "بُومَة", "word"),
        ("burj_khalifa", "بُرْج خَلِيفَة", "word"),
        # clap game: NOT ب
        ("shajara", "شَجَرَة", "word"),
        ("tifl", "طِفْل", "word"),
        ("asad", "أَسَد", "word"),
        ("jamal", "جَمَل", "word"),
        ("arnab", "أَرْنَب", "word"),
        # shapes + quiz
        ("habl", "حَبْل", "word"),
        ("kutub", "كُتُب", "word"),
        ("battiikh", "بَطِّيخ", "word"),
        ("qubbaa", "قُبَّعَة", "word"),
        ("kalb", "كَلْب", "word"),
        # Speak sentences
        ("hadha_bayt", "هَذَا بَيْت", "sentence"),
        ("hadha_baab", "هَذَا بَاب", "sentence"),
        ("hadhihi_batta", "هَذِهِ بَطَّة", "sentence"),
        ("hadhihi_baqara", "هَذِهِ بَقَرَة", "sentence"),
        ("hadha_burj_khalifa", "هَذَا بُرْج خَلِيفَة", "sentence"),
    ],
    # Words already in an earlier set (بَطَّة، بَاب، جَمَل…) are not repeated:
    # the library file is shared.
    "meem": [
        ("mawza", "مَوْزَة", "word"),
        ("miftaah", "مِفْتَاح", "word"),
        ("musht", "مُشْط", "word"),
        ("maa", "مَا", "word"),
        ("maa_water", "مَاء", "word"),
        ("mii", "مِي", "word"),
        ("miidaaliya", "مِيدَالِيَة", "word"),
        ("muu", "مُو", "word"),
        ("muusiiqaa", "مُوسِيقَى", "word"),
        ("misbaah", "مِصْبَاح", "word"),
        ("milaqa", "مِلْعَقَة", "word"),
        ("laymuuna", "لَيْمُونَة", "word"),
        ("najma", "نَجْمَة", "word"),
        ("samaka", "سَمَكَة", "word"),
        ("dubb", "دُبّ", "word"),
        ("qalam", "قَلَم", "word"),
        ("namir", "نَمِر", "word"),
        ("fam", "فَم", "word"),
        # Speak sentences (new speak section in meem.json)
        ("hadha_misbaah", "هَذَا مِصْبَاح", "sentence"),
        ("hadha_miftaah", "هَذَا مِفْتَاح", "sentence"),
        ("hadhihi_mawza", "هَذِهِ مَوْزَة", "sentence"),
        ("hadhihi_milaqa", "هَذِهِ مِلْعَقَة", "sentence"),
        ("hadha_musht", "هَذَا مُشْط", "sentence"),
    ],
    "dal": [
        ("dajaaja", "دَجَاجَة", "word"),
        ("dirham", "دِرْهَم", "word"),
        ("daa", "دَا", "word"),
        ("daaira", "دَائِرَة", "word"),
        ("dii", "دِي", "word"),
        ("diik", "دِيك", "word"),
        ("duu", "دُو", "word"),
        ("duuda", "دُودَة", "word"),
        ("dumya", "دُمْيَة", "word"),
        ("darraaja", "دَرَّاجَة", "word"),
        ("dhiib", "ذِئْب", "word"),
        ("madrasa", "مَدْرَسَة", "word"),
        ("yad", "يَد", "word"),
        ("hadiyya", "هَدِيَّة", "word"),
        ("walad", "وَلَد", "word"),
        # Speak sentences (new speak section in dal.json)
        ("hadhihi_dajaaja", "هَذِهِ دَجَاجَة", "sentence"),
        ("hadha_diik", "هَذَا دِيك", "sentence"),
        ("hadha_dubb", "هَذَا دُبّ", "sentence"),
        ("hadhihi_dumya", "هَذِهِ دُمْيَة", "sentence"),
        ("hadhihi_darraaja", "هَذِهِ دَرَّاجَة", "sentence"),
    ],
    "seen": [
        ("sitta", "سِتَّة", "word"),
        ("sukkar", "سُكَّر", "word"),
        ("saa", "سَا", "word"),
        ("saaa", "سَاعَة", "word"),
        ("sii", "سِي", "word"),
        ("siinamaa", "سِينَمَا", "word"),
        ("suu", "سُو", "word"),
        ("suuq", "سُوق", "word"),
        ("sabbuura", "سَبُّورَة", "word"),
        ("sariir", "سَرِير", "word"),
        ("safiina", "سَفِينَة", "word"),
        # Azure said "misatara" with marks; plain spelling reads it right
        ("mistara", "مِسْطَرَة", "word", "مسطره"),
        ("shams", "شَمْس", "word"),
        ("baskawiit", "بَسْكَوِيت", "word"),
        ("khams", "خَمْس", "word"),
        ("hadhihi_samaka", "هَذِهِ سَمَكَة", "sentence"),
        ("hadhihi_saaa", "هَذِهِ سَاعَة", "sentence"),
        ("hadhihi_sabbuura", "هَذِهِ سَبُّورَة", "sentence"),
        ("hadha_sariir", "هَذَا سَرِير", "sentence"),
        ("hadhihi_safiina", "هَذِهِ سَفِينَة", "sentence"),
        ("ana_araa_samaka", "أَنَا أَرَى سَمَكَة", "sentence"),
        ("ana_araa_saaa", "أَنَا أَرَى سَاعَة", "sentence"),
        ("ana_araa_sabbuura", "أَنَا أَرَى سَبُّورَة", "sentence"),
        ("ana_araa_sariiraa", "أَنَا أَرَى سَرِيرَا", "sentence"),
        ("ana_araa_safiina", "أَنَا أَرَى سَفِينَة", "sentence"),
    ],
    "alif": [
        # alif has no vowel examples, so Speak plays these lone sounds: check them
        ("a", "أَ", "word"),
        ("i", "إِ", "word"),
        ("u", "أُ", "word"),
        ("aa", "آ", "word"),
        ("ii", "إِي", "word"),
        ("uu", "أُو", "word"),
        ("anf", "أَنْف", "word"),
        ("ab", "أَب", "word"),
        ("umm", "أُمّ", "word"),
        ("akh", "أَخ", "word"),
        ("ukht", "أُخْت", "word"),
        ("usra", "أُسْرَة", "word"),
        ("ana", "أَنَا", "word"),
        ("ahmar", "أَحْمَر", "word"),
        ("azraq", "أَزْرَق", "word"),
        ("akhdar", "أَخْضَر", "word"),
        ("aakul", "آكُل", "word"),
        ("aadam", "آدَم", "word"),
        ("ahlan", "أَهْلًا", "word"),
        ("hadha_ana", "هَذَا أَنَا", "sentence"),
        ("ana_ismii", "أَنَا اسْمِي", "sentence"),
        ("ana_uhibbu_abii", "أَنَا أُحِبُّ أَبِي", "sentence"),
        ("ana_uhibbu_ummii", "أَنَا أُحِبُّ أُمِّي", "sentence"),
        ("ana_uhibbu_alarnab", "أَنَا أُحِبُّ الأَرْنَب", "sentence"),
        ("ana_uhibbu_alasad", "أَنَا أُحِبُّ الأَسَد", "sentence"),
        ("ana_uhibbu_allawn_alahmar", "أَنَا أُحِبُّ اللَّوْن الأَحْمَر", "sentence"),
    ],
    # Colours + adjectives (both forms) for the story / colour sentences
    # (Story Maker, Treasure Hunt cards, Feed Juju clues). أَحْمَر أَزْرَق أَخْضَر
    # are already in "alif", so they are not repeated here.
    "juju_world": [
        ("colour_red_f", "حَمْرَاء", "word"),
        ("colour_blue_f", "زَرْقَاء", "word"),
        ("colour_green_f", "خَضْرَاء", "word"),
        ("colour_yellow_m", "أَصْفَر", "word"),
        ("colour_yellow_f", "صَفْرَاء", "word"),
        ("colour_white_m", "أَبْيَض", "word"),
        ("colour_white_f", "بَيْضَاء", "word"),
        ("colour_black_m", "أَسْوَد", "word"),
        ("colour_black_f", "سَوْدَاء", "word"),
        ("colour_brown_m", "بُنِّيّ", "word"),
        ("colour_brown_f", "بُنِّيَّة", "word"),
        ("colour_orange_m", "بُرْتُقَالِيّ", "word"),
        ("colour_orange_f", "بُرْتُقَالِيَّة", "word"),
        ("colour_pink_m", "وَرْدِيّ", "word"),
        ("colour_pink_f", "وَرْدِيَّة", "word"),
        ("colour_purple_m", "بَنَفْسَجِيّ", "word"),
        ("colour_purple_f", "بَنَفْسَجِيَّة", "word"),
        ("colour_grey_m", "رَمَادِيّ", "word"),
        ("colour_grey_f", "رَمَادِيَّة", "word"),
        ("adj_big_m", "كَبِير", "word"),
        ("adj_big_f", "كَبِيرَة", "word"),
        ("adj_small_m", "صَغِير", "word"),
        ("adj_small_f", "صَغِيرَة", "word"),
        ("adj_long_m", "طَوِيل", "word"),
        ("adj_long_f", "طَوِيلَة", "word"),
        ("adj_short_m", "قَصِير", "word"),
        ("adj_short_f", "قَصِيرَة", "word"),
        ("adj_round_m", "مُسْتَدِير", "word"),
        ("adj_round_f", "مُسْتَدِيرَة", "word"),
        ("adj_heavy_m", "ثَقِيل", "word"),
        ("adj_heavy_f", "ثَقِيلَة", "word"),
        ("adj_light_m", "خَفِيف", "word"),
        ("adj_light_f", "خَفِيفَة", "word"),
        ("adj_new_m", "جَدِيد", "word"),
        ("adj_new_f", "جَدِيدَة", "word"),
        ("adj_old_m", "قَدِيم", "word"),
        ("adj_old_f", "قَدِيمَة", "word"),
        ("adj_clean_m", "نَظِيف", "word"),
        ("adj_clean_f", "نَظِيفَة", "word"),
        ("adj_beautiful_m", "جَمِيل", "word"),
        ("adj_beautiful_f", "جَمِيلَة", "word"),
        ("adj_shiny_m", "لَامِع", "word"),
        ("adj_shiny_f", "لَامِعَة", "word"),
        ("adj_colourful_m", "مُلَوَّن", "word"),
        ("adj_colourful_f", "مُلَوَّنَة", "word"),
        ("adj_soft_m", "نَاعِم", "word"),
        ("adj_soft_f", "نَاعِمَة", "word"),
        ("adj_hard_m", "صُلْب", "word"),
        ("adj_hard_f", "صُلْبَة", "word"),
        ("adj_cold_m", "بَارِد", "word"),
        ("adj_cold_f", "بَارِدَة", "word"),
        ("adj_warm_m", "دَافِئ", "word"),
        ("adj_warm_f", "دَافِئَة", "word"),
        ("adj_full_m", "مُمْتَلِئ", "word"),
        ("adj_full_f", "مُمْتَلِئَة", "word"),
        ("adj_empty_m", "فَارِغ", "word"),
        ("adj_empty_f", "فَارِغَة", "word"),
        ("adj_fast_m", "سَرِيع", "word"),
        ("adj_fast_f", "سَرِيعَة", "word"),
        ("adj_delicious_m", "لَذِيذ", "word"),
        ("adj_delicious_f", "لَذِيذَة", "word"),
        ("adj_sweet_m", "حُلْو", "word"),
        ("adj_sweet_f", "حُلْوَة", "word"),
        ("adj_sour_m", "حَامِض", "word"),
        ("adj_sour_f", "حَامِضَة", "word"),
        ("adj_fresh_m", "طَازَج", "word"),
        ("adj_fresh_f", "طَازَجَة", "word"),
        ("adj_happy_m", "سَعِيد", "word"),
        ("adj_happy_f", "سَعِيدَة", "word"),
        ("adj_funny_m", "مُضْحِك", "word"),
        ("adj_funny_f", "مُضْحِكَة", "word"),
    ],
    # Treasure Hunt words (65 in arabic_cache.json); words already in a
    # lesson set (بَاب، بَطَّة…) are not repeated.
    "hunt": [
        ("hunt_sofa", "أَرِيكَة", "word"),
        ("hunt_television", "تِلْفَاز", "word"),
        ("hunt_chair", "كُرْسِيّ", "word"),
        ("hunt_shelf", "رَفّ", "word"),
        ("hunt_carpet", "سَجَّادَة", "word"),
        ("hunt_window", "نَافِذَة", "word"),
        ("hunt_box", "صُنْدُوق", "word"),
        ("hunt_picture", "صُورَة", "word"),
        ("hunt_table", "طَاوِلَة", "word"),
        ("hunt_envelope", "ظَرْف", "word"),
        ("hunt_bicycle", "دَرَّاجَة", "word"),
        ("hunt_toy_frog", "ضِفْدَع", "word"),
        ("hunt_toy_train", "قِطَار", "word"),
        ("hunt_book", "كِتَاب", "word"),
        ("hunt_ball", "كُرَة", "word"),
        ("hunt_block", "مُكَعَّب", "word"),
        ("hunt_toy_car", "سَيَّارَة", "word"),
        ("hunt_toy_bus", "حَافِلَة", "word"),
        ("hunt_paper", "وَرَقَة", "word"),
        ("hunt_yoyo", "يُويُو", "word"),
        ("hunt_juice", "عَصِير", "word"),
        ("hunt_orange", "بُرْتُقَالَة", "word"),
        ("hunt_egg", "بَيْضَة", "word"),
        ("hunt_apple", "تُفَّاحَة", "word"),
        ("hunt_cheese", "جُبْن", "word"),
        ("hunt_milk", "حَلِيب", "word"),
        ("hunt_bread", "خُبْز", "word"),
        ("hunt_corn", "ذُرَة", "word"),
        ("hunt_chocolate", "شُكُولَاتَة", "word"),
        ("hunt_honey", "عَسَل", "word"),
        ("hunt_rice", "أَرُزّ", "word"),
        ("hunt_butter", "زُبْدَة", "word"),
        ("hunt_jam", "مُرَبَّى", "word"),
        ("hunt_fridge", "ثَلَّاجَة", "word"),
        ("hunt_washing_machine", "غَسَّالَة", "word"),
        ("hunt_cup", "كُوب", "word"),
        ("hunt_plate", "صَحْن", "word"),
        ("hunt_fork", "شَوْكَة", "word"),
        ("hunt_bottle", "زُجَاجَة", "word"),
        ("hunt_blanket", "بَطَّانِيَّة", "word"),
        ("hunt_trousers", "بِنْطَال", "word"),
        ("hunt_dress", "فُسْتَان", "word"),
        ("hunt_toothbrush", "فُرْشَاة أَسْنَان", "word"),
        ("hunt_shoe", "حِذَاء", "word"),
        ("hunt_bag", "حَقِيبَة", "word"),
        ("hunt_phone", "هَاتِف", "word"),
        ("hunt_towel", "مِنْشَفَة", "word"),
        ("hunt_comb", "مِشْط", "word"),
        ("hunt_glasses", "نَظَّارَة", "word"),
        ("hunt_shirt", "قَمِيص", "word"),
        ("hunt_soap", "صَابُون", "word"),
        ("hunt_pillow", "وِسَادَة", "word"),
    ],
}


def _hunt_sentences():
    """The 5 Treasure Hunt sentences per word, from assets/data/sentence_bank.json
    (Azure reads `audio_text`). Sentences already in a lesson set are skipped."""
    bank = ROOT / "assets" / "data" / "sentence_bank.json"
    if not bank.exists():
        return []
    have = {lex_key(e[1]) for s in SETS.values() for e in s}
    out = []
    for w in json.loads(bank.read_text(encoding="utf-8")):
        for n, sen in enumerate(w.get("sentences", []), 1):
            ar = sen.get("audio_text") or sen.get("arabic") or ""
            k = lex_key(ar)
            if not ar or k in have:
                continue
            have.add(k)
            out.append((f"{w['id']}_s{n}", ar, "sentence"))
    return out


def lex_key(text):
    """Same as Lex.exact() in lib/data/lex.dart: every mark kept except
    sukun, no punctuation, single spaces. (Exact, so أَ and إِ stay apart;
    the app also falls back to a looser match.)"""
    k = text.replace("\u0652", "")
    k = re.sub("[؟?!.،,:]", "", k)
    return re.sub(r"\s+", " ", k).strip()


def spoken(text):
    """What is sent to Azure: no sukun, final ة written as ه,
    final ى written as ا (Azure dropped it: مُوسِيقَى -> "moseeq")."""
    t = text.replace("\u0652", "").strip()
    t = re.sub("ة(?=[؟?!.،]*$)", "ه", t)
    return re.sub("ى(?=[؟?!.،]*$)", "ا", t)


def item(entry):
    """(name, arabic, kind, text for Azure). A 4th field in SETS overrides
    what Azure reads (sent exactly as written) for a word it mispronounces."""
    name, ar, kind = entry[:3]
    return name, ar, kind, (entry[3] if len(entry) > 3 else spoken(ar))


def ssml(say, kind):
    esc = html.escape(say, quote=True)
    body = f'<prosody rate="{WORD_RATE}">{esc}</prosody>' if kind == "word" else esc
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
            f'xml:lang="ar-AE"><voice name="{VOICE}">{body}'
            '<break time="500ms"/></voice></speak>')


def azure():
    k = os.environ.get("AZURE_TTS_KEY", "")
    r = os.environ.get("AZURE_TTS_REGION", "")
    s = ROOT / "secrets.json"
    if s.exists():
        j = json.loads(s.read_text(encoding="utf-8"))
        k, r = k or j.get("AZURE_TTS_KEY", ""), r or j.get("AZURE_TTS_REGION", "")
    if not k:
        sys.exit("No AZURE_TTS_KEY (environment or secrets.json).")
    return k, r or "uaenorth"


def synth(say, kind, out, k, region):
    req = urllib.request.Request(
        f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1",
        data=ssml(say, kind).encode("utf-8"),
        headers={"Ocp-Apim-Subscription-Key": k,
                 "Content-Type": "application/ssml+xml",
                 "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
                 "User-Agent": "ArabicBuddy"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    if not data:
        raise RuntimeError("empty audio")
    out.write_bytes(data)


def checklist(set_name, items):
    rows = "".join(
        f'<tr><td class="ar">{html.escape(ar)}</td><td>{name}</td>'
        f'<td><audio controls preload="none" src="../assets/audio/lex/{name}.mp3"></audio></td>'
        f'<td><label><input type="checkbox" value="{name}"> wrong</label></td></tr>'
        for name, ar, *_ in items)
    page = f"""<!doctype html><meta charset="utf-8"><title>{set_name} checklist</title>
<style>body{{font-family:sans-serif;margin:20px}}td,th{{border:1px solid #ccc;padding:6px}}
table{{border-collapse:collapse}}.ar{{font-size:28px;direction:rtl}}button{{font-size:18px;margin:16px 0}}</style>
<h1>{set_name}: listen to each one, tick the wrong ones</h1>
<table><tr><th>Arabic</th><th>file</th><th>listen</th><th></th></tr>{rows}</table>
<button onclick="go()">Copy the list for Claude</button><pre id="out"></pre>
<script>
function go(){{
  const bad=[...document.querySelectorAll('input:checked')].map(i=>i.value);
  const t=bad.length?'{set_name} wrong: '+bad.join(', '):'{set_name}: all OK';
  document.getElementById('out').textContent=t;
  navigator.clipboard&&navigator.clipboard.writeText(t);
}}
</script>"""
    TEST_DIR.mkdir(exist_ok=True)
    p = TEST_DIR / f"lex_{set_name}.html"
    p.write_text(page, encoding="utf-8")
    return p


def _story_lines():
    """Every sentence Story Maker can build: each hunt word x every colour x
    big/small/none x happy/funny/none x every pair of its fact adjectives.
    Uses the SAME builder as the app (story.py + arabic_forms.py + phon.py,
    copied into tools/) and the data in assets/data/. The set is finite
    (~2,700 lines), so every story line gets a natural, pre-made recording.
    New colours/adjectives later = just run this set again (only new lines
    are made). Files are named by a hash of the text, so names never shift."""
    import hashlib, importlib, itertools
    tools = Path(__file__).resolve().parent
    cache = tools / "story_lines.json"      # listing all lines takes ~30 s,
    rebuild = any(x in ("story", "all") for x in sys.argv[1:2])  # so reuse it
    if cache.exists() and not rebuild:
        return [tuple(e) for e in json.loads(cache.read_text(encoding="utf-8"))]
    if not (tools / "story.py").exists():
        print("  (story set: copy story.py, arabic_forms.py, phon.py into tools/)")
        return []
    sys.path.insert(0, str(tools))
    here = os.getcwd()
    os.chdir(ROOT / "assets" / "data")      # story.py reads its JSON from the cwd
    try:
        S = importlib.import_module("story")
    finally:
        os.chdir(here)
    # Audio needs only the Arabic: switch off the phonetic spelling (a word
    # with a missing phonetic field would otherwise stop the whole run).
    S.noun_ph = lambda *a, **k: "x"
    S.adj_ph = lambda *a, **k: "x"
    S.waqf_ph = lambda p, *a, **k: p

    class _Order:                            # replaces random: tries every order
        def __init__(self, order): self.order = order
        def shuffle(self, x): x[:] = [x[i] for i in self.order if i < len(x)]

    have = {lex_key(e[1]) for s in SETS.values() for e in s}
    out = []
    for it in S.ITEMS:
      try:
        n = len(it.get("adjectives", [])) + 1
        firsts = list(itertools.permutations(range(n), 2)) if n > 1 else [(0,)]
        for colour in list(S.COL) + [None]:
            for size in ("big", "small", None):
                for fun in (None, "happy", "funny"):
                    for f in firsts:
                        order = list(f) + [i for i in range(n) if i not in f]
                        for ln in S.make_story(it, colour, size, fun, _Order(order)):
                            ar = ln["audio_text"]
                            k = lex_key(ar)
                            if k in have:
                                continue
                            have.add(k)
                            h = hashlib.md5(k.encode("utf-8")).hexdigest()[:10]
                            out.append((f"story_{it['id']}_{h}", ar, "sentence"))
      except Exception as e:
        print(f"  SKIP story for {it.get('id')}: {type(e).__name__}: {e}")
    cache.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    return out


SETS["hunt_sentences"] = _hunt_sentences()
SETS["story"] = _story_lines()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set", choices=sorted(SETS) + ["all"])
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", nargs="*", default=[])
    a = ap.parse_args()
    if not (ROOT / "assets").is_dir():
        sys.exit("Run this from the folder that contains assets/ "
                 "(the Flutter project or your Arabic Buddy folder).")

    names = sorted(SETS) if a.set == "all" else [a.set]
    LEX_DIR.mkdir(parents=True, exist_ok=True)
    old = json.loads(LEX_JSON.read_text(encoding="utf-8")) if LEX_JSON.exists() else {}
    ok_by_file = {v.get("file"): v.get("ok", False) for v in old.values() if isinstance(v, dict)}

    k = region = None
    failed, remade = 0, set()
    for set_name in names:
        print(f"== {set_name}")
        for entry in SETS[set_name]:
            name, ar, kind, say = item(entry)
            out = LEX_DIR / f"{name}.mp3"
            if out.exists() and not (a.force or name in a.only):
                print("  have ", name)
                continue
            if k is None:
                k, region = azure()
            try:
                synth(say, kind, out, k, region)
                remade.add(f"lex/{name}.mp3")
                print("  made ", name, say)
                time.sleep(0.15)
            except Exception as e:
                failed += 1
                print("  FAIL ", name, e)

    # index = every entry of every set whose file exists
    lex = {}
    for set_name, items in SETS.items():
        for entry in items:
            name, ar, kind, _ = item(entry)
            f = f"lex/{name}.mp3"
            if not (LEX_DIR / f"{name}.mp3").exists():
                continue
            key = lex_key(ar)
            if key in lex:
                print(f"  NOTE  {ar} is in two sets; keeping {lex[key]['file']}")
                continue
            lex[key] = {"file": f, "set": set_name,
                        "ok": ok_by_file.get(f, False) and f not in remade}
    LEX_JSON.parent.mkdir(parents=True, exist_ok=True)
    LEX_JSON.write_text(json.dumps(lex, ensure_ascii=False, indent=1), encoding="utf-8")

    pages = [checklist(n, SETS[n]) for n in names]
    print(f"\n{failed} failed. Index: {LEX_JSON.relative_to(ROOT)} ({len(lex)} entries)")
    for p in pages:
        print(f"Checklist: {p.relative_to(ROOT)}  (open in Chrome)")
    print("pubspec.yaml must list:  - assets/audio/lex/")


if __name__ == "__main__":
    main()