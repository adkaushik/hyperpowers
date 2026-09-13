import { useState } from 'react'
import { CheckIcon, CopyIcon } from './icons'

export default function CopyCommand({
  command,
  prompt = '$',
}: {
  command: string
  prompt?: string
}) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(command)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      // Clipboard permission denied — the text is on screen and selectable.
    }
  }

  return (
    <div className="cmd">
      <span className="cmd-prompt" aria-hidden="true">
        {prompt}
      </span>
      <code className="!border-0 !bg-transparent !p-0 whitespace-pre">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        className="ml-auto flex flex-shrink-0 items-center gap-1.5 rounded-md border border-[var(--line)] px-2 py-1 text-[0.6875rem] font-semibold text-[var(--ink-soft)] transition hover:border-[var(--ink-dim)] hover:text-[var(--ink)]"
      >
        {copied ? <CheckIcon size={12} /> : <CopyIcon size={12} />}
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}
