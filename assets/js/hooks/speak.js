// Pronounces Korean text with the browser's speech synthesis (Web Speech API).
//
//   <button id="..." phx-hook="Speak" data-text="안녕하세요" data-rate="0.9">
//
// If the element has a `data-audio` URL (pre-generated audio), that file is
// played instead, so pages upgrade automatically once recorded audio exists.

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
    const {text, audio, rate} = this.el.dataset

    if (audio) {
      const player = new Audio(audio)
      player.playbackRate = parseFloat(rate || "1")
      this.playing(player.play().then(() => new Promise(resolve => (player.onended = resolve))))
      return
    }

    if (!("speechSynthesis" in window)) {
      this.warn("Your browser can't speak text aloud.")
      return
    }

    const utterance = new SpeechSynthesisUtterance(text)
    utterance.lang = "ko-KR"
    utterance.rate = parseFloat(rate || "0.9")

    const voice = koreanVoice()
    if (voice) {
      utterance.voice = voice
    } else if (window.speechSynthesis.getVoices().length > 0) {
      this.warn("No Korean voice is installed; add one in your system's speech settings.")
    }

    window.speechSynthesis.cancel()
    this.playing(
      new Promise(resolve => {
        utterance.onend = resolve
        utterance.onerror = resolve
        window.speechSynthesis.speak(utterance)
      })
    )
  },

  playing(promise) {
    this.el.dataset.speaking = ""
    promise.finally(() => delete this.el.dataset.speaking)
  },

  warn(message) {
    this.el.title = message
    console.warn(`[Speak] ${message}`)
  },
}

export default Speak
