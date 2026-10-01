// Pronounces Korean text, trying three sources in order:
//
//   1. `data-audio` - a clip the page already found, played straight away
//   2. `data-remote` - ask the server to synthesize it, over "audio:speak"
//      (answered by HangukoWeb.AudioHook), then play what comes back
//   3. the browser's own speech synthesis (Web Speech API)
//
//   <button id="..." phx-hook="Speak" data-text="안녕하세요" data-rate="0.9"
//           data-audio="/audio/4f/2a/4f2ab1c3.mp3" data-remote="true">
//
// Each step falls through to the next on failure, so a missing clip or a
// provider outage degrades to a worse voice rather than to silence.

// Clips synthesized during this page's life, by text, so pressing the same
// button twice is one round trip. Clips are immutable, so there is nothing to
// invalidate; the map goes away with the page.
const synthesized = new Map()

// How long to wait for the server before speaking the text locally instead.
// Long enough for a cold synthesis including the provider's own retries, short
// enough that a learner isn't left wondering whether the button did anything.
const REMOTE_TIMEOUT_MS = 4000

// Only one pronunciation is ever audible, across every button on the page.
let playing = null

const stopPlaying = () => {
  if (playing) {
    playing.pause()
    // Settles whatever is waiting on this clip, so the button that started it
    // stops pulsing. Pausing on its own fires no event.
    playing.dispatchEvent(new Event("ended"))
    playing = null
  }
  if ("speechSynthesis" in window) {
    window.speechSynthesis.cancel()
  }
}

const isKorean = voice => voice.lang.replace("_", "-").toLowerCase().startsWith("ko")

const koreanVoice = () => {
  const voices = window.speechSynthesis.getVoices().filter(isKorean)
  // Prefer higher-quality voices when the OS offers several.
  return voices.find(v => /premium|enhanced|natural|google/i.test(v.name)) || voices[0]
}

const Speak = {
  mounted() {
    this.onClick = event => {
      event.preventDefault()
      event.stopPropagation()
      this.speak()
    }
    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },

  speak() {
    stopPlaying()
    this.el.dataset.speaking = ""
    this.pronounce().finally(() => delete this.el.dataset.speaking)
  },

  async pronounce() {
    const {text, audio, remote} = this.el.dataset
    const url = audio || synthesized.get(text)

    if (url) {
      return this.play(url, text)
    }

    if (remote) {
      const synthesizedUrl = await this.requestClip(text)
      if (synthesizedUrl) {
        return this.play(synthesizedUrl, text)
      }
    }

    return this.speakLocally(text)
  },

  // Resolves to a URL, or to null when the server request fails for
  // whatever reason.
  requestClip(text) {
    return new Promise(resolve => {
      const timer = setTimeout(() => resolve(null), REMOTE_TIMEOUT_MS)
      this.pushEvent("audio:speak", {text}, reply => {
        clearTimeout(timer)

        if (reply && reply.url) {
          synthesized.set(text, reply.url)
          resolve(reply.url)
        } else {
          this.warn(`the server didn't pronounce this (${reply && reply.error})`)
          resolve(null)
        }
      })
    })
  },

  async play(url, text) {
    const player = new Audio(url)
    player.playbackRate = parseFloat(this.el.dataset.rate || "1")
    player.preservesPitch = true
    playing = player

    const outcome = new Promise(resolve => {
      player.onended = () => resolve("ended")
      player.onerror = () => resolve("failed")
    })

    try {
      await player.play()
    } catch (error) {
      this.warn(`couldn't play ${url} (${error.message})`)
      return this.speakLocally(text)
    }

    // A clip whose row outlived its file answers 404 here, which is what
    // `mix hanguko.audio.generate --verify` exists to repair.
    if ((await outcome) === "failed") {
      this.warn(`${url} stopped playing`)
      return this.speakLocally(text)
    }
  },

  speakLocally(text) {
    if (!("speechSynthesis" in window)) {
      this.warn("Your browser can't speak text aloud.")
      return
    }

    const utterance = new SpeechSynthesisUtterance(text)
    utterance.lang = "ko-KR"
    utterance.rate = parseFloat(this.el.dataset.rate || "0.9")

    const voice = koreanVoice()
    if (voice) {
      utterance.voice = voice
    } else if (window.speechSynthesis.getVoices().length > 0) {
      this.warn("No Korean voice is installed; add one in your system's speech settings.")
    }

    return new Promise(resolve => {
      utterance.onend = resolve
      utterance.onerror = resolve
      window.speechSynthesis.speak(utterance)
    })
  },

  warn(message) {
    this.el.title = message
    console.warn(`[Speak] ${message}`)
  },
}

export default Speak
