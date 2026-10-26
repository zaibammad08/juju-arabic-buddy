# Before the hackathon vs built during

The hackathon runs **Oct 26 – Nov 4, 2026**. As a startup entry we build on earlier preparation; this page states clearly what existed before and what is new.

## Existed before Oct 26, 2026

- Five printable/web home lessons for the letters ا ب م د س, made earlier for home use. Their lesson *design* is reused as content; the app screens that present them are new.
- Learning content preparation and human review: word lists, sentence templates, adjectives and colours.
- Private helper scripts (not in this repository), written before the event: vowel-mark and grammar rules, sentence/story builders, an audio generator and an image generator. They are only **run** during the hackathon to create the app's assets (see below). The grammar logic the app needs at runtime is rebuilt inside the app during the hackathon.
- A few test images of the Juju character made in the Meta AI app, only to choose and finalize the character looks (not used in the app).
- Test audio clips used to choose voices (not used in the app).
- Screen sketches (HTML mock-ups).

## Built during the hackathon (Oct 26 – Nov 4, 2026)
- The complete Flutter app (all screens, navigation, progress, gallery, writing wall, Juju Corner).
- Every Meta Model API integration: Muse Spark photo recognition and colour, Muse Voice Transcribe speaking check, Muse Spark handwriting check / hints / parent summary, Muse Image sticker and story-picture edit chain with Muse Spark verification.
- **All images used in the app** (Juju master and poses, word stickers, scenes) generated with **Muse Image through the Meta Model API during the event**.
- **All audio used in the app** generated during the event (Azure Text-to-Speech).
- Testing with children, demo video.

A daily log of what was added is kept below and in the commit history.

## Daily log
| Date | What was built |
|---|---|
| Oct 26 | Repository created; licences, structure and sample content added |
