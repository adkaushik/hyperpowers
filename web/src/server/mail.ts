import '@tanstack/react-start/server-only'
import nodemailer, { type Transporter } from 'nodemailer'
import { MAIL_FROM, SMTP, isProduction } from './env'

type Mail = {
  to: string
  subject: string
  text: string
  html: string
}

/**
 * One pooled transport per process: SMTP connections are expensive to set up
 * and sign-in traffic arrives in bursts.
 */
let transporter: Transporter | null = null

function getTransporter() {
  if (transporter) return transporter

  transporter = SMTP.url
    ? // Connection-string form carries its own options: append `?pool=true`
      // to the URL to pool these connections too.
      nodemailer.createTransport(SMTP.url)
    : nodemailer.createTransport({
        host: SMTP.host,
        port: SMTP.port,
        // Port 465 is implicit TLS; everything else starts plaintext and is
        // upgraded by STARTTLS, which `requireTLS` makes non-optional.
        secure: SMTP.secure ?? SMTP.port === 465,
        requireTLS: true,
        auth: SMTP.user ? { user: SMTP.user, pass: SMTP.pass } : undefined,
        pool: true,
      })

  return transporter
}

async function sendWithSmtp(mail: Mail) {
  // Never log `mail.text` or `mail.html` from a failure path — they carry the
  // sign-in code.
  await getTransporter().sendMail({
    from: MAIL_FROM,
    to: mail.to,
    subject: mail.subject,
    text: mail.text,
    html: mail.html,
  })
}

/** Verifies the SMTP credentials without sending anything. */
export async function verifyMailTransport() {
  if (!SMTP.configured) return false
  await getTransporter().verify()
  return true
}

function sendToConsole(mail: Mail) {
  // Development transport. The code is printed because there is nowhere else
  // for it to go; this branch is unreachable in production (see below).
  console.info(
    [
      '',
      '  ┌─ hyperpowers · dev mail transport ─────────────────────────',
      `  │ to:      ${mail.to}`,
      `  │ subject: ${mail.subject}`,
      ...mail.text.split('\n').map((line) => `  │ ${line}`),
      '  └────────────────────────────────────────────────────────────',
      '',
    ].join('\n'),
  )
}

/**
 * Sends mail through whichever transport is configured. In production a
 * missing transport throws rather than silently dropping the message, because
 * a dropped sign-in code looks identical to a wrong code from the outside.
 */
export async function sendMail(mail: Mail) {
  if (SMTP.configured) {
    await sendWithSmtp(mail)
    return
  }
  if (isProduction) {
    throw new Error(
      'No mail transport configured. Set SMTP_URL (or SMTP_HOST) and MAIL_FROM before serving production traffic.',
    )
  }
  sendToConsole(mail)
}

export function loginCodeMail(email: string, code: string, ttlMinutes: number) {
  const spaced = `${code.slice(0, 3)} ${code.slice(3)}`
  return {
    to: email,
    subject: `${code} is your Hyperpowers sign-in code`,
    text: [
      `Your Hyperpowers sign-in code is ${spaced}.`,
      '',
      `It expires in ${ttlMinutes} minutes and can be used once.`,
      'If you did not request it, you can ignore this email.',
    ].join('\n'),
    html: `<!doctype html>
<html>
  <body style="margin:0;padding:32px;background:#0b0d0f;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#e6e8ea">
    <table role="presentation" style="max-width:480px;margin:0 auto;border-collapse:collapse">
      <tr><td>
        <p style="margin:0 0 24px;font:600 13px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.14em;text-transform:uppercase;color:#e0a83d">hyperpowers</p>
        <h1 style="margin:0 0 12px;font-size:20px;font-weight:600;color:#f4f5f6">Your sign-in code</h1>
        <p style="margin:0 0 24px;font-size:14px;line-height:1.6;color:#9aa1a8">Enter this code in the browser tab you started from.</p>
        <p style="margin:0 0 24px;padding:18px 24px;border:1px solid #23282e;border-radius:12px;background:#12151a;font:700 30px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.28em;color:#f4f5f6;text-align:center">${code}</p>
        <p style="margin:0;font-size:13px;line-height:1.6;color:#6f767d">Expires in ${ttlMinutes} minutes. Single use. If you did not request it, ignore this email.</p>
      </td></tr>
    </table>
  </body>
</html>`,
  }
}
