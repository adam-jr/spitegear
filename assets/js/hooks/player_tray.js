function parseHex(hex) {
  const h = hex.replace('#', '')
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

function sanitizeColor(colorStr) {
  if (!colorStr || !colorStr.startsWith('#') || colorStr.length < 7) return colorStr
  let [r, g, b] = parseHex(colorStr)
  if (r > 220 && g > 220 && b > 220) return '#888888'
  if (r === 0 && g === 0 && b === 0) return colorStr
  const lum = 0.299 * r + 0.587 * g + 0.114 * b
  const MIN_LUM = 65
  if (lum < MIN_LUM) {
    const scale = MIN_LUM / lum
    r = Math.min(255, Math.round(r * scale))
    g = Math.min(255, Math.round(g * scale))
    b = Math.min(255, Math.round(b * scale))
    return '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('')
  }
  return colorStr
}

const PlayerTray = {
  mounted() {
    this._players = JSON.parse(this.el.dataset.players || '[]')
    this._colors = JSON.parse(this.el.dataset.colors || '{}')
    this._expanded = false
    this._visible = false

    if (this._players.length === 0) return

    this._build()
    this._setupScrollWatcher()
    this.el.addEventListener('click', () => this._toggle())
  },

  destroyed() {
    if (this._scrollListener) window.removeEventListener('scroll', this._scrollListener)
  },

  _build() {
    const players = this._players
    const colors = this._colors

    const chipsEl = this.el.querySelector('[data-tray-chips]')
    chipsEl.innerHTML = ''
    players.forEach(name => {
      const color = sanitizeColor(colors[name]) || '#888888'
      const chip = document.createElement('span')
      chip.className = 'flex items-center gap-1.5 px-2.5 py-1.5 rounded-full text-xs font-medium text-gray-100'
      chip.innerHTML =
        `<span aria-hidden="true" style="color:${color};font-size:10px;line-height:1;flex-shrink:0">●</span>` +
        `<span>${name}</span>`
      chipsEl.appendChild(chip)
    })

    const dotsEl = this.el.querySelector('[data-tray-dots]')
    dotsEl.innerHTML = players.map(name => {
      const color = sanitizeColor(colors[name]) || '#888888'
      return `<span aria-hidden="true" style="color:${color};font-size:9px;line-height:1">●</span>`
    }).join('')

    const countEl = this.el.querySelector('[data-tray-count]')
    if (countEl) countEl.textContent = `${players.length} Players`
  },

  _toggle() {
    this._expanded = !this._expanded
    this._syncExpanded()
  },

  _syncExpanded() {
    const content = this.el.querySelector('[data-tray-content]')
    const arrow = this.el.querySelector('[data-tray-arrow]')
    if (this._expanded) {
      content.style.maxHeight = content.scrollHeight + 'px'
      if (arrow) arrow.textContent = '▼'
    } else {
      content.style.maxHeight = '0'
      if (arrow) arrow.textContent = '▲'
    }
  },

  _setupScrollWatcher() {
    const chartsEl = document.getElementById('charts-section')
    if (!chartsEl) return

    const check = () => {
      const rect = chartsEl.getBoundingClientRect()
      const inView = window.scrollY > 150 && rect.top < window.innerHeight - 50 && rect.bottom > 50
      if (inView === this._visible) return
      this._visible = inView
      if (inView) {
        this.el.style.transform = 'translateY(0)'
      } else {
        this.el.style.transform = 'translateY(100%)'
        if (this._expanded) {
          this._expanded = false
          this._syncExpanded()
        }
      }
    }

    this._scrollListener = check
    window.addEventListener('scroll', check, { passive: true })
  },
}

export default PlayerTray
