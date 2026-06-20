const ConsoleInput = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
        e.preventDefault()
        this.el.closest("form").requestSubmit()
      }
    })
  }
}

export default ConsoleInput
