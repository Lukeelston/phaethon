// A recorder must reject incomplete/reversed outcomes before it replaces a known-good fixture.
'use strict';
const assert = require('assert');
const proof = require('./replay_proof.js');
const course = { lap: 188.8, crash: false, hits: 0 };
const makeJob = (kind) => ({
  end: { stage: kind === 'late' ? 'failed' : 'done' }, hits: 0,
  events: [[10, 'job', 'drop'], [20, 'job', 'home'], [30, 'job', kind === 'late' ? 'failed' : 'done']],
  job: { stage: kind === 'late' ? 'failed' : 'done', reason: kind === 'late' ? 'dawn' : '', route: kind === 'shade' ? 'shade' : 'open', margin: kind === 'late' ? 0 : 15 }
});
assert.throws(() => proof.course({ ...course, lap: null }), /completed lap/);
assert.throws(() => proof.course({ ...course, lap: NaN }), /completed lap/);
assert.throws(() => proof.course({ ...course, crash: true }), /crash/);
assert.throws(() => proof.course({ ...course, hits: 1 }), /wall hit/);
proof.course(course);
for (const kind of ['open', 'shade', 'late']) proof.job(kind, makeJob(kind));
assert.throws(() => proof.job('open', { ...makeJob('open'), end: null }), /terminal/);
assert.throws(() => proof.job('open', makeJob('late')), /success/);
assert.throws(() => proof.job('shade', makeJob('open')), /route/);
assert.throws(() => proof.job('late', makeJob('open')), /dawn/);
const early = makeJob('late');
early.events = [[30, 'dawn', ''], [30, 'job', 'failed']];
assert.throws(() => proof.job('late', early), /delivery/);
const reversed = makeJob('open');
reversed.events = [[10, 'job', 'home'], [20, 'job', 'drop'], [30, 'job', 'done']];
assert.throws(() => proof.job('open', reversed), /delivery/);
const expired = makeJob('open');
expired.job.margin = -0.1;
assert.throws(() => proof.job('open', expired), /margin/);
console.log('REPLAY PROOF PASS');
