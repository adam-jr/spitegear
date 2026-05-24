import Chart from "../../vendor/chart.umd.min.js"

const COLORS = [
  "rgb(59,130,246)",   // blue
  "rgb(239,68,68)",    // red
  "rgb(34,197,94)",    // green
  "rgb(245,158,11)",   // amber
  "rgb(168,85,247)",   // purple
  "rgb(20,184,166)",   // teal
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
    let isDragging = false
    let dragStartX = 0
    let dragStartMin = null
    let dragStartMax = null

    const onWheel = (e) => {
      e.preventDefault()
      if (!this.chart) return
      const xScale = this.chart.scales.x
      const rect = canvas.getBoundingClientRect()
      const mouseX = e.clientX - rect.left
      const pct = (mouseX - xScale.left) / xScale.width
      const range = xScale.max - xScale.min
      const factor = e.deltaY < 0 ? 0.8 : 1 / 0.8
      const newRange = range * factor
      const newMin = xScale.min + pct * (range - newRange)
      xScale.options.min = newMin
      xScale.options.max = newMin + newRange
      this.chart.update("none")
    }

    const onMousedown = (e) => {
      if (!this.chart) return
      isDragging = true
      dragStartX = e.clientX
      dragStartMin = this.chart.scales.x.min
      dragStartMax = this.chart.scales.x.max
      canvas.style.cursor = "grabbing"
    }

    const onMousemove = (e) => {
      if (!isDragging || !this.chart) return
      const xScale = this.chart.scales.x
      const range = dragStartMax - dragStartMin
      const deltaUnits = ((e.clientX - dragStartX) / xScale.width) * range
      xScale.options.min = dragStartMin - deltaUnits
      xScale.options.max = dragStartMax - deltaUnits
      this.chart.update("none")
    }

    const stopDrag = () => {
      isDragging = false
      canvas.style.cursor = ""
    }

    canvas.addEventListener("wheel", onWheel, { passive: false })
    canvas.addEventListener("mousedown", onMousedown)
    canvas.addEventListener("mousemove", onMousemove)
    canvas.addEventListener("mouseup", stopDrag)
    canvas.addEventListener("mouseleave", stopDrag)

    this._zoomCleanup = () => {
      canvas.removeEventListener("wheel", onWheel)
      canvas.removeEventListener("mousedown", onMousedown)
      canvas.removeEventListener("mousemove", onMousemove)
      canvas.removeEventListener("mouseup", stopDrag)
      canvas.removeEventListener("mouseleave", stopDrag)
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
