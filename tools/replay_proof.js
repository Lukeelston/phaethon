'use strict';

function course(run) {
  if (!Number.isFinite(run.lap) || run.lap <= 0) throw new Error('Recording refused: no completed lap.');
  if (run.crash) throw new Error('Recording refused: lap crashed.');
  if (run.hits !== 0) throw new Error('Recording refused: lap has wall hits.');
}

function job(kind, run) {
  const j = run.job;
  if (!run.end || !['done', 'failed'].includes(j.stage) || run.end.stage !== j.stage) throw new Error('Recording refused: job has no terminal outcome.');
  if (run.hits !== 0) throw new Error('Recording refused: job has wall hits.');
  const stages = run.events.filter(e => e[1] === 'job').map(e => e[2]);
  const drop = stages.indexOf('drop'), home = stages.indexOf('home'), terminal = stages.indexOf(j.stage);
  if (drop < 0 || home <= drop || terminal <= home) throw new Error('Recording refused: job did not complete the delivery and return sequence.');
  if (kind === 'late') {
    if (j.stage !== 'failed' || j.reason !== 'dawn') throw new Error('Recording refused: late route was not caught by dawn.');
  } else {
    if (j.stage !== 'done' || j.reason !== '') throw new Error('Recording refused: expected job success.');
    if (j.route !== kind) throw new Error('Recording refused: job finished on the wrong route.');
    if (!Number.isFinite(j.margin) || j.margin <= 0) throw new Error('Recording refused: success has no positive dawn margin.');
  }
}

module.exports = { course, job };
