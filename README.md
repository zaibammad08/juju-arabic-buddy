#  Juju Arabic Buddy

**School Arabic at home, for children whose parents don't speak Arabic.**

Built for the **Meta Global AI Developer Hackathon 2026** · Startup track · Theme: **Build for Your World**
Built by **WowDesignAI** (Abu Dhabi, UAE) during the hackathon, **26 October – 4 November 2026**.

📹 **Demo video:** 
📱 **Android APK:** 


> **Muse understands the child's world. Arabic Buddy controls what the child learns.**

---

## The problem

In the UAE, children learn Arabic at school from their early years. In many expat families, the parents don't speak or read Arabic themselves. When Arabic homework comes home, parents turn to Google Translate or guesswork, and children lose interest.

Before building, **we surveyed 62 parents**. Most have young children; the largest groups were aged 5, 6 and 7, the age range Arabic Buddy is designed for.

| What parents told us | Responses |
|---|---:|
| Feel completely lost helping with Arabic homework | 23 (37%) |
| Only somewhat confident, relying on Google Translate | 28 (45%) |
| **Cannot confidently support Arabic homework** | **51 of 62 (82%)** |
| Child is not interested (25) or frustrated (8) when practising at home | 33 (53%) |
| Biggest challenge: no English support for parents | 29 (47%) |
| Biggest challenge: too classroom-focused, not fun at home | 13 (21%) |

Not every family has this problem: 13 parents said there was no issue. But for most, **the gap isn't a lack of Arabic content. It's the missing link between what children learn at school and what parents can support at home, in a language they understand.**

## What Arabic Buddy does

Juju, a friendly baby camel, guides children aged 4–7 through the letters their school teaches (ا ب م د س), using the child's own home as the classroom.

**1. My Letter: all four skills.** Every letter is practised through **Listen** (hear the letter in familiar words), **Speak** (sounds and words with body moves), **Read** (find the letter at the start, middle or end of a word) and **Write** (trace it with a finger), in the school's order.

**2. Treasure Hunt.** The child photographs real things at home, like a door, a cup or a chair. Juju names each one in Arabic, the child says the word and colours it in, and every find becomes a page of the child's own illustrated mini-story.

**3. Juju's Magic World.** Camera games that only work in the real world:
- **Detective:** find the object from Arabic and English clues.
- **Feed Juju:** read three Arabic clue words (like *red · round · fruit*) and bring Juju something that matches all three.
- **Playdough Magic:** shape the letter in playdough and show it to the camera.
- **Story Maker:** turn discoveries into simple Arabic sentences.
- **Treasure Unlock:** complete challenges to unlock rewards.

**4. Parent Corner.** Arabic basics in plain English, progress by letter and skill, a weekly report written for parents, and **Ask Juju** for homework questions, answered in English. Parents don't need to know Arabic to take part.

## How Meta's models power Arabic Buddy

Meta's models handle what needs understanding of images, speech and context. The Arabic itself (vocabulary, sentences, grammar and the learning order) comes from reviewed content and app rules.

| What happens | Meta model |
|---|---|
| Lesson-building tools  from the arabic language pdfs and parts of the app code | **Muse Code** |
| Recognise objects and colours in the child's photos | **Muse Spark** (vision) |
| Check Magic World answers: does this object match the clues? Is this playdough shape the letter? | **Muse Spark** (vision) |
| Kind handwriting check on the child's traced letter | **Muse Spark** (vision) |
| Adaptive hints when the child is stuck | **Muse Spark** |
| Weekly parent report and Ask Juju answers in English | **Muse Spark** |
| Check the child's spoken Arabic word | **Muse Voice Transcribe** |
| Juju's poses, word stickers and illustrated story pages | **Muse Image** |
| Check each story picture matches its sentence before the child sees it | **Muse Spark** |


### From a lesson plan to an interactive lesson
Our lesson plans follow the school's letter sequence. They were written and checked by a person before the hackathon. During the event we used **Muse Code** to build tools that turn each lesson plan into structured lesson data (JSON) covering all four skills: words for each letter position, a listening quiz, vowel sounds with example words, speaking sentences and tracing. A person checks the result (vowel marks, meanings, pictures) before it is loaded into the app. A new letter becomes a full Listen, Speak, Read and Write lesson in hours, not weeks, still with human review.

**No textbook pages are included in the app or this repository.** Lessons use the school's letter sequence and everyday vocabulary, with our own sentences, pictures and audio.

## Safe by design for young children

- **Reviewed Arabic.** AI never writes the Arabic the child learns. Every word and sentence comes from human-reviewed content with full vowel marks.
- **Rule-based grammar.** Case endings and masculine/feminine agreement are applied by app rules, not generated.
- **Reviewed audio.** All audio is pre-made and checked by ear, word by word. No speech service is called while the app runs.
- **Photos stay on the family's phone.** Each photo is sent only for its single AI check, and nothing is kept on our servers. Parents can clear all photos and progress in Settings.

## Validation

### 62 parents surveyed
The results above shaped our focus: English support for parents, fun practice at home, and lessons that match school.
Evidence: 
 (https://forms.gle/EDPpW6kpKJhxFxum8)
 (https://docs.google.com/spreadsheets/d/1epfZQ5pWoT1iNOiSfxbLg3awwG6dk9mTcNEQ68__Xek/edit?usp=sharing)
[docs/evidence/](docs/evidence/)

### Reviewed by the Head of Arabic B, GEMS Founders School, Abu Dhabi
We shared Arabic Buddy with **Mr Mohamed Essam Eldean, Head of Arabic B at GEMS Founders School, Abu Dhabi**, for feedback on its content and vision:

> "I was genuinely impressed by the quality and depth of the application… What makes the platform particularly valuable is that it addresses all the key language skills young learners need, including listening, speaking, reading, and writing, while providing meaningful support for parents to guide their children's learning at home."
>
> "The app creates an effective bridge between school and home learning, enabling parents to actively participate in their children's language development."

Full feedback: [docs/evidence/teacher-feedback.png](docs/evidence/teacher-feedback.png) (shared with his permission).

Arabic Buddy doesn't replace the school or the teacher. It makes it easier for parents to reinforce classroom learning at home.

### Tested with children
Tested at home with children, who helped check the vocabulary and the activities.

## Built during the hackathon (26 Oct – 4 Nov 2026)

**Built during the event:** the complete Flutter app; the four-skill letter lessons; Treasure Hunt and Juju's Magic World; Parent Corner and Ask Juju; progress, gallery and writing wall; every Meta model integration above; the Muse Code lesson tools; all images (generated with **Muse Image**); and all audio (pre-made with Azure Text-to-Speech, reviewed by ear).

**Existed before, and reused only as content:** five lesson plans for ا ب م د س (written and checked by a person), word lists, a few voice and character test files, and HTML screen sketches.

Full timeline: [docs/BEFORE_AND_DURING.md](docs/BEFORE_AND_DURING.md). The commit history starts on 26 Oct 2026.

## Run it

**Requirements:** Flutter 3.22+ (Dart 3.4+) and a Meta Model API key. The easiest way to try it is the Android APK linked at the top.

1. Clone the repository:
   ```bash
   git clone https://github.com/zaibammad08/juju-arabic-buddy
   cd juju-arabic-buddy
   ```
2. Create `secrets.json` in the project root (it is git-ignored):
   ```json
   { "META_API_KEY": "your-key" }
   ```
3. Get the packages and run:
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=secrets.json
   ```

Without a key, the letter lessons and audio still work; the camera, voice and parent features need the key.

*Note: for this hackathon build the key is passed in at build time. A production app would send AI requests through a secure backend instead of shipping a key inside the app.*

## Project layout

```text
lib/
  screens/          all app screens (magic/ = Juju's Magic World games)
  services/         Meta model clients (meta_vision, meta_voice, meta_text,
                    meta_image, meta_games), offline audio player, progress
  data/             lesson data loading, Arabic grammar rules, word library lookup
  widgets/          Juju, buttons, shared UI
assets/
  data/             lessons, words, sentences, word library index (lex.json)
  audio/            pre-made audio (lex/ = one reviewed file per word)
  images/           stickers, Juju poses and scenes (Muse Image)
tools/              scripts that made and checked the audio and lessons
docs/               before/during log, evidence
```

## Licence

© 2026 WowDesign Artificial Intelligence LLC SPC.
- **Code:** MIT licence (see [LICENSE](LICENSE)).
- **Juju, images, audio and learning content:** all rights reserved (see [CONTENT_LICENSE.md](CONTENT_LICENSE.md)). Included so the app can be run and judged, not for reuse.

**Arabic Buddy: because learning Arabic should be a journey the whole family can enjoy.**
www.wowdesignai.com