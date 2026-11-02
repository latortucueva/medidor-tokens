import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionMeasureInput, SessionUsage } from 'claude-code'

import type { Medida } from '../types'

const medida = atom({ plugin: 'medidor-tokens', key: 'medida' } as const, null)

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`)

const nombre = (kind: string) =>
  kind === 'five_hour' ? 'Límite 5 h' : kind === 'seven_day' ? 'Semana' : kind

const DIAS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb']

const hora = (iso: string | null) => {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ''
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  const hoy = new Date()
  const esHoy = d.getFullYear() === hoy.getFullYear() && d.getMonth() === hoy.getMonth() && d.getDate() === hoy.getDate()
  const dia = esHoy ? 'hoy' : `${DIAS[d.getDay()]} ${d.getDate()}/${d.getMonth() + 1}`
  return ` (se renueva ${dia} ${hh}:${mm})`
}

const barra = (p: number) => {
  const n = Math.max(0, Math.min(10, Math.round(p / 10)))
  return '█'.repeat(n) + '░'.repeat(10 - n)
}

async function guardar($: EngineInterface, e: SessionUsage | SessionMeasureInput) {
  const m: Medida = {
    tokens: e.context.tokens ?? null,
    window: e.context.window,
    percent: e.context.percent ?? null,
    limits: e.rateLimits.map(r => ({ kind: r.kind, percentUsed: r.percentUsed, resetsAt: r.resetsAt ?? null })),
    usd: e.cost?.usd ?? null,
  }
  await update($, medida, () => m)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    try {
      await guardar($, await $.session.usage())
    } catch {}
    return r
  })

  on('session.measure', async ($, e, next) => {
    await guardar($, e)
    for (const l of e.rateLimits) {
      if (l.percentUsed >= 90) $.ui.toast(`${nombre(l.kind)}: ${Math.round(l.percentUsed)}% usado`)
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const m = await read($, medida)
    if (m === null || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const pct = m.percent ?? (m.tokens !== null && m.window ? (m.tokens / m.window) * 100 : null)
    const ctx = pct === null ? `ventana ${k(m.window)}` : `${barra(pct)} ${Math.round(pct)}% · ${m.tokens !== null ? k(m.tokens) : '?'} / ${k(m.window)}`
    return (
      <Box flexDirection="column">
        <Text>
          <Text color="green">Contexto </Text>
          {ctx}
        </Text>
        {m.limits.map(l => (
          <Text key={l.kind}>
            <Text color={l.percentUsed >= 80 ? 'red' : 'green'}>{nombre(l.kind)} </Text>
            {barra(l.percentUsed)} {Math.round(l.percentUsed)}% usado · {Math.max(0, 100 - Math.round(l.percentUsed))}% libre{hora(l.resetsAt)}
          </Text>
        ))}
      </Box>
    )
  })
}
