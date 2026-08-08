'use strict'

// Measure two built output directories and render one size-delta fragment.
//
// Both builds already happened; this only reads them. Every size axis below
// comes off the same dist/, which is the point — never rebuild per metric.

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')
const { formatBytes, deltaLabel, sizeTable } = require('./delta.cjs')

// CONFIGURE: how a chunk is recognised as third-party, and how to strip the
// content hash so the same logical chunk can be compared across two builds.
const VENDOR_PATTERN = /-vendor-|[/\\]vendor[-.]/
const STRIP_HASH = /-[A-Za-z0-9_-]{8}(\.[a-z]+)$/

/**
 * Measure the eager-load set: everything index.html references directly, which
 * is what a first paint must download. Lazy chunks are excluded on purpose —
 * they are the part of the bundle a user may never fetch.
 *
 * CONFIGURE: for a non-HTML entry point (a library, a server bundle), replace
 * this with a walk over the output directory.
 */
function measure(dist) {
	const indexPath = path.join(dist, 'index.html')
	if (!fs.existsSync(indexPath)) {
		throw new Error(`no index.html in ${dist} — adapt measure() to this project's output`)
	}
	const html = fs.readFileSync(indexPath, 'utf8')
	const files = [
		...new Set([...html.matchAll(/assets\/[A-Za-z0-9._-]+\.(?:js|css)/g)].map((m) => m[0])),
	]

	const total = { js: { raw: 0, gz: 0 }, css: { raw: 0, gz: 0 } }
	const vendors = {}
	let entry = { raw: 0, gz: 0 }

	for (const rel of files) {
		const buf = fs.readFileSync(path.join(dist, rel))
		const raw = buf.length
		const gz = zlib.gzipSync(buf).length
		const name = rel.slice(rel.lastIndexOf('/') + 1)

		if (name.endsWith('.css')) {
			// Render-blocking on first paint, so it belongs in the eager cost —
			// but on its own axis, because it moves for different reasons than JS.
			total.css.raw += raw
			total.css.gz += gz
			continue
		}
		total.js.raw += raw
		total.js.gz += gz

		if (VENDOR_PATTERN.test(name)) {
			vendors[name.replace(STRIP_HASH, '$1')] = { file: name, raw, gz }
		} else if (/^index[-.]/.test(name)) {
			entry = { raw, gz }
		}
	}
	return { ...total, entry, vendors }
}

/**
 * Compare vendor chunks by identity, not size. An unchanged content hash means
 * returning visitors still have it cached, which matters more than its weight.
 */
function vendorSection(base, head) {
	const names = [...new Set([...Object.keys(base.vendors), ...Object.keys(head.vendors)])].sort()
	if (!names.length) return '_No vendor chunks in the eager set._'

	const changed = []
	let cachedRaw = 0
	let cachedGz = 0
	let cachedCount = 0

	for (const n of names) {
		const b = base.vendors[n]
		const h = head.vendors[n]
		if (b && h && b.file === h.file) {
			cachedCount++
			cachedRaw += h.raw
			cachedGz += h.gz
		} else {
			changed.push({ n, b, h })
		}
	}

	if (!changed.length) {
		return (
			`✅ **Vendor chunks unchanged** — ${cachedCount} chunk(s) totalling ` +
			`${formatBytes(cachedRaw)} raw (${formatBytes(cachedGz)} gzipped), still cached for repeat visitors.`
		)
	}

	const rows = changed.map(({ n, b, h }) => {
		if (!b) return `- 🆕 \`${n}\` added — ${formatBytes(h.raw)} raw (${formatBytes(h.gz)} gz)`
		if (!h) return `- ❌ \`${n}\` removed — was ${formatBytes(b.raw)} raw`
		return `- 🔺 \`${n}\` — ${formatBytes(b.raw)} → ${formatBytes(h.raw)} raw (${deltaLabel(h.raw, b.raw)})`
	})
	const stable =
		cachedCount ?
			`\n\n${cachedCount} other vendor chunk(s) unchanged — ${formatBytes(cachedRaw)} raw (${formatBytes(cachedGz)} gz), still cached.`
		:	''
	return `**Vendor chunks changed:**\n${rows.join('\n')}${stable}`
}

module.exports = function render({ head, base, out }) {
	fs.mkdirSync(out, { recursive: true })
	const h = measure(head)
	const b = measure(base)

	const markdown = [
		'#### Bundle size',
		'',
		'**Eager load** — the entry chunk plus every preload in `index.html` (what a first paint downloads)',
		'',
		sizeTable(h.js.raw, h.js.gz, b.js.raw, b.js.gz),
		'',
		'**Entry chunk** — your own code, re-downloaded on every deploy',
		'',
		sizeTable(h.entry.raw, h.entry.gz, b.entry.raw, b.entry.gz),
		'',
		'**CSS** — render-blocking on first paint',
		'',
		sizeTable(h.css.raw, h.css.gz, b.css.raw, b.css.gz),
		'',
		vendorSection(b, h),
	].join('\n')

	fs.writeFileSync(path.join(out, '40-bundle.md'), markdown)
	fs.writeFileSync(
		path.join(out, '40-bundle.json'),
		JSON.stringify(
			{
				check: 'bundle',
				eagerRawDelta: h.js.raw - b.js.raw,
				eagerGzDelta: h.js.gz - b.js.gz,
				entryGzDelta: h.entry.gz - b.entry.gz,
			},
			null,
			2
		)
	)
}

module.exports.measure = measure
