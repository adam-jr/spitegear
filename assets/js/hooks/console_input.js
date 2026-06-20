const ConsoleInput = {
  mounted() {
    this.cmdHistory = []
    this.historyIndex = -1
    this.draft = ""

    this.handleEvent("history_updated", ({history}) => {
      this.cmdHistory = history
      this.historyIndex = -1
      this.draft = ""
    })

    this.el.addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
        e.preventDefault()
        this.el.closest("form").requestSubmit()
        return
      }

      if (e.key === "ArrowUp") {
        const beforeCursor = this.el.value.substring(0, this.el.selectionStart)
        if (!beforeCursor.includes("\n") && this.cmdHistory.length > 0) {
          e.preventDefault()
          if (this.historyIndex === -1) this.draft = this.el.value
          this.historyIndex = Math.min(this.historyIndex + 1, this.cmdHistory.length - 1)
          this.el.value = this.cmdHistory[this.historyIndex]
          this.el.setSelectionRange(0, 0)
        }
      }

      if (e.key === "ArrowDown" && this.historyIndex > -1) {
        const afterCursor = this.el.value.substring(this.el.selectionEnd)
        if (!afterCursor.includes("\n")) {
          e.preventDefault()
          this.historyIndex -= 1
          const val = this.historyIndex === -1 ? this.draft : this.cmdHistory[this.historyIndex]
          this.el.value = val
          this.el.setSelectionRange(val.length, val.length)
        }
      }
    })
  }
}

export default ConsoleInput
