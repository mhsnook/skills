'use strict'

// Assemble the fragments and upsert the single PR comment.
//
// `actions/github-script` hands this the authenticated octokit, so the
// workflow step stays one line:
//
//   script: await require('./.github/ci/post-comment.cjs')({ github, context, core })
//
// The octokit arrives as an argument rather than a token this file reads for
// itself, which is the whole point: no credential is named here, so this file
// can be reviewed and edited as ordinary code.

const MARKER = '### PR checks'

// CONFIGURE: markers from a previous layout, so the stale comments they wrote
// get cleaned up on the next run. Leave empty on a first install.
const RETIRED_MARKERS = []

module.exports = async function postComment({ github, context, core }, opts = {}) {
	const { assemble, upsertComment, retireComments } = require('./comment.cjs')
	const fragments = opts.fragments ?? '/tmp/fragments'

	const body = assemble(fragments, {
		marker: MARKER,
		header: `_Compared against \`${context.payload.pull_request.base.ref}\`._`,
	})

	if (RETIRED_MARKERS.length) {
		core.info(JSON.stringify(await retireComments(github, context, RETIRED_MARKERS)))
	}
	const result = await upsertComment(github, context, MARKER, body)
	core.info(JSON.stringify(result))
	return result
}

module.exports.MARKER = MARKER
