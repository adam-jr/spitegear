export default {
  mounted() {
    this.pushEvent("client_timezone", {
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
    })
  }
}
