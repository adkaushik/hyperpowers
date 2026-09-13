export function ArrowRightIcon({ size = 14 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" aria-hidden="true" width={size} height={size}>
      <path
        fill="none"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M2.5 8h11M9 3.5 13.5 8 9 12.5"
      />
    </svg>
  )
}

export function CheckIcon({ size = 14 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" aria-hidden="true" width={size} height={size}>
      <path
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 8.5l3.5 3.5L13 4.5"
      />
    </svg>
  )
}

export function CopyIcon({ size = 14 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" aria-hidden="true" width={size} height={size}>
      <g fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="5.75" y="5.75" width="8.5" height="8.5" rx="1.75" />
        <path
          strokeLinecap="round"
          d="M10.25 2.75h-7a1.5 1.5 0 0 0-1.5 1.5v7"
        />
      </g>
    </svg>
  )
}
