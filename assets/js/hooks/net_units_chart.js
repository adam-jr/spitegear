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
  mounted() { this.renderChart() },
  updated() {
    if (this.chart) this.chart.destroy()
    this.renderChart()
  },
  destroyed() {
    if (this.chart) this.chart.destroy()
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
  },
}

export default NetUnitsChart
