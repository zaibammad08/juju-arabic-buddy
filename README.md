# Juju Arabic Buddy 🐪

© 2026 WowDesign Artificial Intelligence LLC SPC. **Code:** MIT licence (see [LICENSE](LICENSE)). **Juju, images, audio and learning content:** all rights reserved (see [CONTENT_LICENSE.md](CONTENT_LICENSE.md)).

Arabic Buddy helps young children (4–7) in the UAE learn school Arabic (Modern Standard Arabic) at home – even when their parents don't speak Arabic. Juju, a baby camel, guides every activity.

Built for the **Meta Global AI Developer Hackathon 2026** · Startup track · Theme: *Build for Your World*.

## The problem
Expat parents in the UAE often can't help with Arabic homework: school apps are built for the classroom, with little English support. Arabic Buddy brings school Arabic into the child's real world at home.

## What it does
- **My Letter** – this week's letter in four skills (listen, speak, read, write), following the school order (ا ب م د س).
- **Treasure Hunt** – the child photographs real objects at home, hears the Arabic word, says it aloud, makes it their own and gets a personal illustrated mini-story.
- **Juju Corner** – playful activities with Juju (feelings, polite words, counting).

## How Meta's models work together
| Step | Meta model |
|---|---|
| Recognise the object (and its colour) in the child's photo | Muse Spark (vision) |
| Check the child's spoken word | Muse Voice Transcribe |
| Kind handwriting check, adaptive hints, parent summary | Muse Spark |
| Stickers, Juju's poses, the child's illustrated story pages (edit chain) | Muse Image |
| Check each generated story picture matches its sentence | Muse Spark |
Arabic text is never written by AI: every word and sentence comes from reviewed content with full vowel marks and rule-based grammar (case endings, masculine/feminine agreement). Photos are checked, then deleted – never stored.

## Before the hackathon vs built during (Oct 26 – Nov 4, 2026)
See [docs/BEFORE_AND_DURING.md](docs/BEFORE_AND_DURING.md). In short: content preparation and small helper scripts existed before; **the app and every Meta model integration are built during the hackathon** – see the commit history.

## Repository layout
```text
app/              Flutter app (built during the hackathon)
sample_content/   a SMALL sample of the learning content (5 letters, 24 words) so the app can run
docs/             the before/during log
