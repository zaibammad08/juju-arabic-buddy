# Before the hackathon vs built during

The hackathon runs **26 Oct – 4 Nov 2026**. As a startup entry we build on earlier preparation. This page states clearly what existed before and what is new. The commit history starts on 26 Oct 2026.

## Existed before 26 Oct 2026 (content and preparation only)

- **Five lesson plans** for the letters ا ب م د س, aligned with the school's letter of the week and **already checked by a person** (words, vowel marks, meanings). They were made earlier as printable/web home lessons. The app uses them as *content*; every screen and activity that presents them is new.
- Word lists, sentence templates, adjectives and colours, prepared and reviewed by a person.
- Private helper scripts (not in this repository): vowel-mark and grammar rules, sentence and story builders, an audio generator and an image generator. They were only **run** during the hackathon to make the app's assets. The grammar logic the app needs at runtime was rebuilt inside the app during the hackathon.
- A few test images of Juju made in the Meta AI app, only to choose the character's look (not used in the app).
- Test audio clips used to choose voices (not used in the app).
- Screen sketches (HTML mock-ups).

## Built during the hackathon (26 Oct – 4 Nov 2026)

- **The complete Flutter app:** every screen, navigation, progress tracking, gallery, writing wall and Parent Corner.
- **Four-skill letter lessons** (Listen, Speak, Read, Write), built from the existing lesson plans.
- **Lesson tools built with Muse Code:** tools that read our own lesson-plan PDFs (the printable home lessons) and turn each one into structured lesson data (JSON) covering all four skills, ready for a person to check and then load into the app. Muse Code also helped write parts of the app code.
- **Juju's Magic World:** five camera games (Detective, Feed Juju, Playdough Magic, Story Maker, Treasure Unlock).
- **Every Meta model integration:**
  - Muse Spark: photo recognition and colour, Magic World checks, handwriting check, hints, parent report, Ask Juju, story-picture check.
  - Muse Voice Transcribe: speaking check.
  - Muse Image: stickers, Juju poses and story pictures.
  - Muse Code: the lesson tools (lesson-plan PDF → lesson JSON) and parts of the app code.
- **All images in the app** (Juju and his poses, word stickers, scenes), generated with **Muse Image** through the Meta Model API during the event.
- **All audio in the app**, generated during the event (Azure Text-to-Speech) and reviewed word by word by ear. It is stored as files in a shared word library, and the app plays only these files (no text-to-speech service is called while it runs).
- Testing with children, the demo video and this documentation.

## Daily log

| Date | What was built |
|---|---|
| 26 Oct | **1:33 PM UAE:** repository created with the default Flutter starter template only (`flutter create`, no Arabic Buddy code). **From 9:35 PM UAE, after kickoff:** licences, security rules, README, project scope and this log |
| 27 Oct | App foundation: theme, data models, Arabic grammar rules rebuilt in the app, shared widgets. Home screen, Treasure Hunt hub, Camera (countdown, Muse Spark vision, offline word picker) |
| 28 Oct | Audio index and asset folders. My Letter hub, Juju's Alphabet, Read (letter shapes and "Where is it hiding?" quiz), Write (tracing with shape check). Hunt hub and Camera updates |
| 29 Oct | New screens; Muse Spark vision and Muse Voice Transcribe updates |
| 30 Oct | Sentences, story, gallery, writing wall, Parent Corner and parent guide |
| 31 Oct | Lesson tools built with Muse Code (lesson-plan PDF → lesson JSON); lesson data checked and loaded; images generated with Muse Image |
| 1 Nov | Juju's Magic World (5 camera games + Muse Spark game service). New hubs (desert-and-sky home, game carousel, skill carousel). Polish of hunt, letter and parent screens. Audio review: offline-only audio, shared word library, re-made unclear words |
| 2 Nov | Survey and teacher-feedback evidence added. Playdough Magic: kinder shape check, second try always celebrates. Audio and word-library updates; lesson and audio tools added. README fixes |
| 3 Nov | In-app camera for Magic World games; Ask Juju fix; live-speech buttons removed. All app assets added to the repo so judges can run the app. README next steps, evidence filename fix |
| 3 Nov | Submission |