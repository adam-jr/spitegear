import Chart from "../../vendor/chart.umd.min.js"

const COLORS = [
  "rgb(59,130,246)",   // blue
  "rgb(239,68,68)",    // red
  "rgb(34,197,94)",    // green
  "rgb(161,84,26)",    // brown
  "rgb(168,85,247)",   // purple
  "rgb(236,72,153)",   // pink
  "rgb(249,115,22)",   // orange
  "rgb(14,165,233)",   // sky
]

const NetUnitsChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("reset-zoom", () => this._resetZoom())
  },
  updated() {
    this._destroyChart()
    this.renderChart()
  },
  destroyed() {
    this._destroyChart()
  },

  renderChart() {
    const series = JSON.parse(this.el.dataset.series)
    const datasets = Object.entries(series)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([player, points], i) => ({
        label: player,
        data: points.map(p => ({ x: p.seq, y: p.net_units })),
        borderColor: COLORS[i % COLORS.length],
        backgroundColor: COLORS[i % COLORS.length],
        fill: false,
        stepped: true,
        pointRadius: 2,
        borderWidth: 2,
      }))

    this.chart = new Chart(this.el, {
      type: "line",
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        scales: {
          x: { type: "linear", title: { display: true, text: "Log Seq" } },
          y: { title: { display: true, text: "Net Units" } },
        },
        plugins: {
          legend: { position: "top" },
        },
      },
    })

    this._setupZoom()
  },

  _destroyChart() {
    this._teardownZoom()
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  },

  _resetZoom() {
    if (!this.chart) return
    const xOpts = this.chart.scales.x.options
    delete xOpts.min
    delete xOpts.max
    this.chart.update("none")
  },

  _setupZoom() {
    const canvas = this.el
    const container = canvas.parentElement
    let isDragging = false
    let dragStartX = 0
    let selectionEl = null

    // Convert a clientX position into a data-space seq value
    const pxToSeq = (clientX) => {
      const xScale = this.chart.scales.x
      const rect = canvas.getBoundingClientRect()
      const pct = (clientX - rect.left - xScale.left) / xScale.width
      return xScale.min + pct * (xScale.max - xScale.min)
    }

    const onMousedown = (e) => {
      if (!this.chart) return
      isDragging = true
      dragStartX = e.clientX
      canvas.style.cursor = "col-resize"

      selectionEl = document.createElement("div")
      selectionEl.style.cssText =
        "position:absolute;top:0;bottom:0;pointer-events:none;" +
        "background:rgba(59,130,246,0.12);border-left:1px solid rgba(59,130,246,0.5);border-right:1px solid rgba(59,130,246,0.5);"
      const cRect = container.getBoundingClientRect()
      selectionEl.style.left = (e.clientX - cRect.left) + "px"
      selectionEl.style.width = "0"
      container.appendChild(selectionEl)
    }

    const onMousemove = (e) => {
      if (!isDragging || !selectionEl) return
      const cRect = container.getBoundingClientRect()
      const startRel = dragStartX - cRect.left
      const nowRel = e.clientX - cRect.left
      selectionEl.style.left = Math.min(startRel, nowRel) + "px"
      selectionEl.style.width = Math.abs(nowRel - startRel) + "px"
    }

    const onMouseup = (e) => {
      if (!isDragging) return
      isDragging = false
      canvas.style.cursor = ""
      if (selectionEl) { selectionEl.remove(); selectionEl = null }

      const dragEndX = e.clientX
      if (Math.abs(dragEndX - dragStartX) < 5) return  // ignore tiny clicks

      const newMin = pxToSeq(Math.min(dragStartX, dragEndX))
      const newMax = pxToSeq(Math.max(dragStartX, dragEndX))

      this.chart.scales.x.options.min = newMin
      this.chart.scales.x.options.max = newMax
      this.chart.update("none")
    }

    const onMouseleave = () => {
      if (!isDragging) return
      isDragging = false
      canvas.style.cursor = ""
      if (selectionEl) { selectionEl.remove(); selectionEl = null }
    }

    canvas.addEventListener("mousedown", onMousedown)
    canvas.addEventListener("mousemove", onMousemove)
    canvas.addEventListener("mouseup", onMouseup)
    canvas.addEventListener("mouseleave", onMouseleave)

    this._zoomCleanup = () => {
      canvas.removeEventListener("mousedown", onMousedown)
      canvas.removeEventListener("mousemove", onMousemove)
      canvas.removeEventListener("mouseup", onMouseup)
      canvas.removeEventListener("mouseleave", onMouseleave)
      if (selectionEl) { selectionEl.remove() }
    }
  },

  _teardownZoom() {
    if (this._zoomCleanup) {
      this._zoomCleanup()
      this._zoomCleanup = null
    }
  },
}

export default NetUnitsChart
