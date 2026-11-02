export type Medida = {
  tokens: number | null
  window: number
  percent: number | null
  limits: { kind: string; percentUsed: number; resetsAt: string | null }[]
  usd: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'medidor-tokens': { medida: Medida | null }
  }
}
