# Lesson to JSON

Turns a teacher's Year 1 Arabic letter lesson (4 PDFs) into one JSON file that the Juju Arabic Buddy app reads (`assets/data/lessons/<letter>.json`).

It is a prompt, not a program. No API key or install needed.

## How to use

1. Open an AI chat that reads PDFs (we use Muse Spark on meta.ai).
2. Open `PROMPT.md`, copy the prompt, and fill in the 4 lines at the top (letter, Arabic name, English name, connects) from the letter table.
3. Upload the 4 lesson PDFs for that one letter. Together they should cover:
   the letter's shape and sound, short vowels (fatha, kasra, damma), letter shapes (beginning, middle, end) and long vowels (aa, ii, uu).
4. Save the reply as `<letter-name>.json`, for example `laam.json`.
5. Check it before use (see below).

## Output

One JSON object with these keys:
`letter, name, shapes, posq, words, not_words, vowels, long_vowels, trace, trace_say, speak`

See `examples/laam.json` for an approved example.

## Check before use

The AI can still make mistakes, so check:

- counts: 3 shapes (2 for ا د ذ ر ز و), 3 posq, 5–8 words, exactly 5 not_words, 3 vowels, 3 long_vowels, 10 speak lines
- `trace_say` starts with the letter's name (for ل: لَام)
- no not_word contains the letter
- each english matches its own word
- هذا / هذه and the أنا أرى forms (have an Arabic teacher check these)

Sticker and audio paths are added by the app, not by this prompt.

## Privacy

Lesson PDFs are not stored in this repo. They are school material and may include photos of children. Keep them on your own device.

## Credits

Lesson content by the Year 1 Arabic team at GEMS Founders School Abu Dhabi. Reviewed by Mohamed Essam Eldean, Head of Arabic B.
