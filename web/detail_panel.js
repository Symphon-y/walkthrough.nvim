/* walkthrough detail panel — renders one entity's evidence/confidence and
 * the accept/challenge/correct controls into the #detail aside. Plain
 * DOM, no framework, matching the rest of this vendored-libraries-only,
 * no-build-step frontend. Badge colors come from CSS classes (see
 * web/styles.css) sourced from the dataviz skill's palette, not inline
 * styles, so theme (light/dark) swaps for free.
 */
window.WalkthroughDetailPanel = (function () {
  'use strict';

  var STATUS_LABEL = {
    proposed: 'Proposed',
    accepted: 'Accepted',
    challenged: 'Challenged',
    corrected: 'Corrected',
    unresolved: 'Unresolved',
  };

  function el(tag, className, text) {
    var e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function badge(text, extraClass) {
    return el('span', 'badge ' + extraClass, text);
  }

  function claimBadgeClass(claim_type) {
    if (claim_type === 'OBSERVED') return 'claim-observed';
    if (claim_type === 'INFERRED') return 'claim-inferred';
    return 'claim-unknown';
  }

  function statusBadgeClass(status) {
    return 'status-' + (status || 'proposed');
  }

  /* Render `entity` (a component/relationship/decision/assumption
   * object -- they all share claim_type/confidence/status/evidence) into
   * the panel and open it. Pass null to close it.
   *
   * actions: { onAccept(), onChallenge(), onCorrect(note) } -- omitted
   * (or entity null) hides the action row entirely. */
  function show(container, entity, actions) {
    container.innerHTML = '';
    if (!entity) {
      container.classList.remove('open');
      return;
    }

    container.appendChild(el('div', 'd-title', entity.name || entity.question || entity.statement || entity.id));
    if (entity.role) {
      container.appendChild(el('div', 'd-role', entity.role));
    }

    var badges = el('div', 'd-badges');
    badges.appendChild(badge(entity.claim_type || 'UNKNOWN', claimBadgeClass(entity.claim_type)));
    if (entity.confidence) {
      badges.appendChild(badge(entity.confidence, 'confidence'));
    }
    badges.appendChild(badge(STATUS_LABEL[entity.status] || entity.status || 'proposed', statusBadgeClass(entity.status)));
    container.appendChild(badges);

    var evidence = entity.evidence || [];
    container.appendChild(el('div', 'd-section-title', 'Evidence'));
    if (evidence.length > 0) {
      evidence.forEach(function (e) {
        var line = e.file + (e.line ? ':' + e.line : '') + (e.symbol ? '  (' + e.symbol + ')' : '');
        container.appendChild(el('div', 'd-evidence', line));
      });
    } else {
      container.appendChild(el('div', 'd-evidence', 'none cited'));
    }

    if (actions) {
      container.appendChild(el('div', 'd-section-title', 'Review'));

      var buttonRow = el('div', 'd-actions');
      var acceptBtn = el('button', 'd-btn d-btn-accept', 'Accept');
      acceptBtn.addEventListener('click', actions.onAccept);
      var challengeBtn = el('button', 'd-btn d-btn-challenge', 'Challenge');
      challengeBtn.addEventListener('click', actions.onChallenge);
      buttonRow.appendChild(acceptBtn);
      buttonRow.appendChild(challengeBtn);
      container.appendChild(buttonRow);

      var noteBox = el('textarea', 'd-note');
      noteBox.placeholder = "What's wrong, or what should this say instead?";
      noteBox.rows = 3;
      container.appendChild(noteBox);

      var correctBtn = el('button', 'd-btn d-btn-correct', 'Submit correction');
      correctBtn.addEventListener('click', function () {
        var note = noteBox.value.trim();
        if (!note) {
          noteBox.focus();
          return;
        }
        actions.onCorrect(note);
      });
      container.appendChild(correctBtn);
    }

    container.appendChild(el('div', 'd-hint', 'Click again to jump to source · click empty canvas to clear focus'));

    container.classList.add('open');
  }

  return { show: show };
})();
