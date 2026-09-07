'use strict'

// Fan-in rendering: take the two artifact trees and produce one directory of
// markdown fragments plus their gate sidecars.
//
//   node render-report.cjs <headArtifactDir> <baseArtifactDir> <outDir>
//
// The head job already rendered its single-tree fragments (tests), so those
// are copied across; everything comparative is rendered here, where both
// summaries are present. Keeping this in a script rather than inline in the
// workflow is what lets you change the report without editing a file that can
// read every secret in the repository.

const fs = require('fs')
const path = require('path')

const renderStatic = require('./render-static.cjs')
const renderBundle = require('./render-bundle.cjs')

function main(headDir, baseDir, out) {
	fs.mkdirSync(out, { recursive: true })

	// A tree whose job crashed leaves no artifact. Render what is present and
	// let gate.cjs fail on the missing sidecar — a missing report is not a pass.
	const carried = path.join(headDir, 'fragments')
	if (fs.existsSync(carried)) fs.cpSync(carried, out, { recursive: true })

	renderStatic({
		head: path.join(headDir, 'static'),
		base: path.join(baseDir, 'static'),
		out,
	})
	renderBundle({
		head: path.join(headDir, 'bundle.json'),
		base: path.join(baseDir, 'bundle.json'),
		out,
	})

	console.log(fs.readdirSync(out).sort().join('\n'))
}

module.exports = main

if (require.main === module) {
	const [headDir, baseDir, out] = process.argv.slice(2)
	main(headDir ?? '/tmp/head', baseDir ?? '/tmp/base', out ?? '/tmp/fragments')
}
