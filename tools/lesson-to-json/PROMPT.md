# Prompt: Arabic letter lesson → JSON

Copy everything inside the box below into a new AI chat (Muse Spark on meta.ai, or any chat that reads PDFs).
Fill in the 4 lines at the top from the letter table at the end of this file, then upload the 4 lesson PDFs for that letter.

```
You convert a Year 1 Arabic letter lesson (4 teacher PDFs) into ONE JSON object.
Output JSON only, no markdown, no explanation. Use ONLY words that appear in the PDFs.

LETTER: ل
NAME (Arabic, with marks): لَام
NAME (English): Laam
CONNECTS: yes        (ا د ذ ر ز و do not connect to the next letter)

Exact shape (all keys required, in this order):
{
 "letter", "name",
 "shapes": 3 items (2 if CONNECTS is no: beginning + end only),
   each {position: beginning|middle|end, form, word, plain, english, emoji},
 "posq": exactly 3 items, one per position, each {word, plain, english, emoji, answer},
 "words": 5–8 items that START with the letter, each {word, plain, english, emoji, phonetic},
 "not_words": EXACTLY 5 items, each {word, plain, english, emoji, phonetic},
 "vowels": exactly 3, in order fatha, kasra, damma:
   {ar:"<letter>َ", say:"<letter>َ", s:"la", mark:"fatha: a small line on top", ex:{e, ar, say, tr, en}}
   kasra mark: "kasra: a small line below"; damma mark: "damma: a little curl on top",
 "long_vowels": exactly 3, in order aa, ii, uu:
   {ar:"<letter>ا", say:"<letter>َا", s:"laa", mark:"with alif: a long a", ex:{e, ar, say, tr, en}}
   marks: "with yaa: a long i", "with waaw: a long u",
 "trace": [letter, word1_plain, word2_plain],
 "trace_say": [[NAME (Arabic), ""], [word1_with_marks, english], [word2_with_marks, english]],
 "speak": exactly 10 items {e, ar, say, tr, en}:
   items 1–5: "هذا X." (masculine) or "هذه X." (feminine, usually ends in ة)
   items 6–10: "أنا أرى X." for the same 5 words. Masculine words without ة take
   tanween fatha: ar "أنا أرى لحمًا.", say ends with "ا" (لَحْمَا). Words with ة stay as they are.
}

RULES
- word / say = full tashkeel. plain / ar = no tashkeel (speak "ar" may keep ًا).
- english is the meaning of THIS word. Never copy the english from another item.
- not_words must NOT contain the letter anywhere (not only at the start).
- Every vowel example must start with the letter carrying that exact mark.
- Long-vowel examples: prefer the teacher's model words from the long-vowel lesson,
  even if the letter is in the middle of the word.
- ي after fatha (as in لَيْمُون) is NOT a long ii. Never use it as a long-vowel example.
- Prefer the teacher's own model words (the "أنا أفعل" slide) for vowels and long vowels.
- speak uses picturable objects only (no night, peace or other abstract words).
- No two items in "words" may share the same english meaning.
- Do NOT output sticker or audio paths.
- phonetic style: aa ii uu for long vowels, ʿ for ع, ʾ for ء, ḥ for ح, ṭ ṣ ḍ ẓ for emphatic letters.
```

## Letter table

| Letter | Name (Arabic) | Name (English) | Connects |
|---|---|---|---|
| ا | أَلِف | Alif | no |
| ب | بَاء | Baa | yes |
| ت | تَاء | Taa | yes |
| ث | ثَاء | Thaa | yes |
| ج | جِيم | Jiim | yes |
| ح | حَاء | Haa | yes |
| خ | خَاء | Khaa | yes |
| د | دَال | Daal | no |
| ذ | ذَال | Dhaal | no |
| ر | رَاء | Raa | no |
| ز | زَاي | Zaay | no |
| س | سِين | Siin | yes |
| ش | شِين | Shiin | yes |
| ص | صَاد | Saad | yes |
| ض | ضَاد | Daad | yes |
| ط | طَاء | Taa (heavy) | yes |
| ظ | ظَاء | Zaa | yes |
| ع | عَيْن | Ayn | yes |
| غ | غَيْن | Ghayn | yes |
| ف | فَاء | Faa | yes |
| ق | قَاف | Qaaf | yes |
| ك | كَاف | Kaaf | yes |
| ل | لَام | Laam | yes |
| م | مِيم | Miim | yes |
| ن | نُون | Nuun | yes |
| ه | هَاء | Haa (soft) | yes |
| و | وَاو | Waaw | no |
| ي | يَاء | Yaa | yes |