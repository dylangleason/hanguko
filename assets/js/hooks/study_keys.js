// Keyboard shortcuts for study sessions.
//
//   Space / Enter   show the answer, or rate "Good" once it is shown
//   1 2 3 4         rate Again / Hard / Good / Easy (once the answer is shown)
//   S               play the pronunciation
//   U, Ctrl/⌘+Z     undo the last rating
//
// The element carries the session state as data attributes:
//   data-revealed   "true" when the answer is shown
//   data-key        identifies the current card, sent along with ratings so a
//                   rating can never apply to a card the learner hasn't seen
//   data-can-undo   "true" when there is a rating to undo

const typing = el => el.closest("input, textarea, select, [contenteditable]")

const StudyKeys = {
  mounted() {
    this.onKeydown = event => {
      if (event.repeat || typing(event.target)) return

      const {revealed, key, canUndo} = this.el.dataset
      const shown = revealed === "true"
      const undoKey = event.key === "u" || (event.key === "z" && (event.metaKey || event.ctrlKey))

      if (undoKey && canUndo === "true") {
        event.preventDefault()
        this.pushEvent("undo", {})
        return
      }

      if (event.metaKey || event.ctrlKey || event.altKey || !key) return

      if (event.key === " " || event.key === "Enter") {
        event.preventDefault()
        shown ? this.pushEvent("rate", {rating: "3", key}) : this.pushEvent("flip", {})
      } else if (shown && ["1", "2", "3", "4"].includes(event.key)) {
        event.preventDefault()
        this.pushEvent("rate", {rating: event.key, key})
      } else if (event.key === "s") {
        const speak = this.el.querySelector("[data-primary-speak]")
        if (speak) speak.click()
      }
    }

    window.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown)
  },
}

export default StudyKeys
