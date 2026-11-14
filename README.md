# 🎵 Vybe

<p align="center">
  <img src="assets/icons/ic_launcher.png" alt="Vybe Logo" width="140" />
</p>

<h1 align="center">Your Music. Your Rules. Your Vybe.</h1>


<p align="center">
  <strong>Done with ads? Ready for a better music experience?</strong>
  <br />
  Stream, discover, download, and enjoy your favourite music — without interruptions.
</p>

<p align="center">
  <a href="https://github.com/Shubham-Loshali/Vybe/releases/tag/v10.6.5">
    <img src="https://img.shields.io/badge/⬇%20DOWNLOAD%20VYBE%20FOR%20ANDROID-GET%20V10.6.5-16C75B?style=for-the-badge&logo=android&logoColor=white&labelColor=111111" alt="Download Vybe" />
  </a>
</p>

<p align="center">
  <a href="https://github.com/Shubham-Loshali/Vybe/releases"><strong>All Releases</strong></a> •
  <a href="#-features"><strong>Features</strong></a> •
  <a href="#-installation"><strong>Installation</strong></a> •
  <a href="#-contributing"><strong>Contribute</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-brightgreen?style=flat-square&logo=android" alt="Platform: Android" />
  <img src="https://img.shields.io/badge/Built%20With-Flutter-blue?style=flat-square&logo=flutter" alt="Built With Flutter" />
  <img src="https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square" alt="License: GPL-3.0" />
  <img src="https://img.shields.io/badge/Version-10.6.5-purple?style=flat-square" alt="Version 10.6.5" />
</p>

---

## 👋 What is this?

**Vybe** is a free, open-source music app for Android, built with **Flutter**.

I got tired of music apps that put ads between songs, hide basic features behind a paywall, and ask for your life story before they let you listen. So Vybe does the opposite: **open it, search a song, hit play.** That's the whole pitch.

It also does a bunch of other stuff, which is below.

---

## ✨ What it can do

### 🎵 Listening
- **Search for pretty much any song** and stream it
- **Plays in the background**, with proper notification and lock-screen controls
- **Works with Android Auto**, so your car gets it too

### 📥 Downloads
- **Save songs or whole playlists** for offline listening
- **Local caching** so things load fast the second time around

### 🟢 Bring your Spotify playlists with you
- **Paste a public Spotify playlist link** and Vybe finds the matching tracks and builds the playlist in your library

### 🎤 Synced lyrics
- **Lyrics that follow along with the song**, with a glow that picks up colors from the album art
- **Tap a line to jump** to that part of the song, or nudge the timing if it's a bit off
- **Lyrics get saved** so they still work offline
- **Song missing lyrics?** Import your own `.lrc` or `.txt` file (UTF-8). Only lines with real timestamps will sync.

### 🎚️ Make it sound right
- **Multi-band equalizer** with custom presets

### 📻 Radio
- **Browse internet radio stations** by genre from all over the world

### 📊 Your stats
- **See your most-played songs and artists**, how long you've been listening, and shareable recap cards
- **There's a "Time Machine" screen** for looking back month by month and year by year

### 🔄 Sync between your own devices
- **Move playlists, favourites, and your library** between phones over the same Wi-Fi. No cloud needed.
- **Prefer cloud sync?** It's optional and runs on *your own* Firebase project, so your data stays in your account and not mine.

### 🎨 Looks
- **Material You design** with dynamic colors on supported phones
- **Light, Dark, and AMOLED black themes**, plus custom accent colors
- **Translated into 20+ languages**

---

## 📲 Getting it

1. **Grab the APK** from the [latest release](https://github.com/Shubham-Loshali/Vybe/releases/tag/v10.6.5).
2. **Open it on your phone.** Android will ask you to allow installs from your browser or file manager, which is normal for apps outside the Play Store.
3. **Done.** Go listen to something.

> You'll need **Android 7.0 (API 24) or newer**.

<!--
## 📸 Screenshots

Add some here! A row of 3-4 phone screenshots goes a long way.
-->

---

## 🧰 Under the hood

| Component | Purpose |
| :--- | :--- |
| **Flutter + Dart** | One codebase, smooth UI |
| **just_audio, audio_service, audio_session** | Playback, background audio, and audio focus |
| **Hive CE** | Local storage and caching |
| **GoRouter** | Navigation |
| **dynamic_color** | Material You theming |
| **RxDart** | Reactive state for the player |

---

## 🤝 Contributing

Found a bug? Want a feature? PRs and issues are very welcome.

1. **Fork the repo**
2. **Make a branch:** `git checkout -b feature/cool-thing`
3. **Make your changes and commit:** `git commit -m "feat: add cool thing"`
4. **Push it and open a Pull Request**

Before you open the PR, give these a run:

```bash
flutter analyze
flutter test test/lyrics
```

---

## 📜 Disclaimer

**Vybe is an independent project.** It isn't affiliated with or endorsed by Spotify, YouTube, or any other music service. All names and trademarks belong to their owners. Where music comes from and how you use it is subject to those providers' terms and the copyright laws where you live.

---

<div align="center">

**Made for people who love music 🎶**
<br />
If Vybe's useful to you, a ⭐ on the repo is a nice way to say thanks.

</div>
