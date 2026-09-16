'use strict'

// Render a test-run fragment. Single-branch: a test either passes on head or
// it does not, so there is nothing to diff against base.
//
// CONFIGURE: `parse` expects the JSON shape your runner emits. The default
// reads Vitest and Jest (`--reporter=json`). Swap it for your runner and leave
// everything below untouched.
//
// `results` may be a FILE or a DIRECTORY of report files. In a workspace, a
// recursive test command starts one runner process per package and each
// resolves `--outputFile` against its own directory, so pointing them all at
// one absolute path leaves only whichever package finished last. Collect the
// reports into a directory and pass that instead.
//
// Pass `outcome` (the test step's own outcome) as well. A runner that dies
// after writing some reports produces files that parse perfectly, and without
// the step outcome that reads as a clean pass.

const fs = require('fs')
const path = require('path')

const CAP = 20

function parse(raw) {
	const r = JSON.parse(raw)
	const failures = []
	for (const file of r.testResults ?? []) {
		for (const t of file.assertionResults ?? []) {
			if (t.status !== 'failed') continue
			failures.push({
				name: [...(t.ancestorTitles ?? []), t.title].join(' › '),
				file: file.name?.replace(process.cwd() + '/', '') ?? '',
				message: (t.failureMessages ?? []).join('\n').split('\n')[0] ?? '',
			})
		}
	}
	return {
		total: r.numTotalTests ?? 0,
		passed: r.numPassedTests ?? 0,
		failed: r.numFailedTests ?? failures.length,
		skipped: r.numPendingTests ?? 0,
		failures,
	}
}

/** Every report file to read: the one file, or every `.json` in the directory. */
function reportFiles(results) {
	if (!fs.existsSync(results)) return []
	if (!fs.statSync(results).isDirectory()) return [results]
	return fs
		.readdirSync(results)
		.filter((f) => f.endsWith('.json'))
		.map((f) => path.join(results, f))
		.sort()
}

/** Add one report's counts and failures to the running total. */
function merge(total, one) {
	return {
		total: total.total + one.total,
		passed: total.passed + one.passed,
		failed: total.failed + one.failed,
		skipped: total.skipped + one.skipped,
		failures: [...total.failures, ...one.failures],
	}
}

module.exports = function render({ results, out, outcome }) {
	fs.mkdirSync(out, { recursive: true })
	const files = reportFiles(results)

	if (!files.length) {
		fs.writeFileSync(
			path.join(out, '50-tests.md'),
			'#### Tests\n\n⚠️ No results file was produced — the runner probably crashed before writing output. Check the job log.'
		)
		// A missing report is a failure, not a pass. Say so to the gate.
		fs.writeFileSync(
			path.join(out, '50-tests.json'),
			JSON.stringify({ check: 'tests', failed: 1, missing: true }, null, 2)
		)
		return
	}

	const s = files
		.map((f) => parse(fs.readFileSync(f, 'utf8')))
		.reduce(merge, { total: 0, passed: 0, failed: 0, skipped: 0, failures: [] })

	// The runner can die after writing some reports. Those files parse perfectly
	// and count zero failures, so without the step's own outcome a crashed run
	// reads as a clean one.
	const crashed = outcome && outcome !== 'success' && s.failed === 0

	const icon = s.failed || crashed ? '❌' : '✅'
	const lines = [
		'#### Tests',
		'',
		`${icon} ${s.passed}/${s.total} passed` +
			(s.failed ? ` · **${s.failed} failed**` : '') +
			(s.skipped ? ` · ${s.skipped} skipped` : '') +
			(files.length > 1 ? ` · ${files.length} report(s) merged` : ''),
	]
	if (crashed) {
		lines.push(
			'',
			`⚠️ The test step reported \`${outcome}\` while every report it wrote counts zero failures. The runner probably died part-way. Check the job log.`
		)
	}

	if (s.failures.length) {
		const shown = s.failures.slice(0, CAP)
		const block = shown
			.map((f) => `✗ ${f.name}\n  ${f.file}\n  ${f.message}`.trimEnd())
			.join('\n\n')
		const more =
			s.failures.length > CAP ? `\n\n… and ${s.failures.length - CAP} more` : ''
		lines.push('', `**Failed (${s.failures.length}):**`, '', '```', block + more, '```')
	}

	fs.writeFileSync(path.join(out, '50-tests.md'), lines.join('\n'))
	fs.writeFileSync(
		path.join(out, '50-tests.json'),
		JSON.stringify(
			{
				check: 'tests',
				// A crashed runner counts as one failure, so the gate blocks.
				failed: crashed ? 1 : s.failed,
				total: s.total,
				reports: files.length,
			},
			null,
			2
		)
	)
}
