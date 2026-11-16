(() => {
  'use strict';
  let language = 'zh';
  let group = 'feature';
  const languageButton = document.querySelector('#language');
  const groupButtons = [...document.querySelectorAll('[data-group]')];
  const t = (zh, en) => language === 'zh' ? zh : en;
  function updateGroup() {
    const feature = group === 'feature';
    groupButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.group === group)));
    document.querySelector('[data-repo="app"]').textContent = feature ? 'feature/search' : 'main';
    document.querySelector('[data-repo="library"]').textContent = feature ? 'feature/search' : 'main';
    document.querySelectorAll('.match-reason').forEach(node => {
      node.textContent = feature ? t('同名分支自动匹配', 'Matched by branch name') : t('使用主检出目录', 'Uses primary checkout');
    });
    document.querySelector('.fallback-reason').textContent = feature ? t('无对应工作树，沿用主目录', 'No matching worktree; uses primary') : t('使用主检出目录', 'Uses primary checkout');
    document.querySelector('#selection-summary').textContent = feature ? t('两仓库匹配 feature/search，SDK 沿用主目录。', 'Two repositories match feature/search; the SDK uses its primary checkout.') : t('三个仓库均浏览主检出目录，不要求它们的分支同名。', 'All three repositories use their primary checkouts, regardless of branch names.');
  }
  function setLanguage(next) {
    language = next;
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.querySelectorAll('[data-zh]').forEach(node => { node.textContent = node.dataset[language]; });
    for (const attribute of ['alt', 'aria']) {
      document.querySelectorAll(`[data-zh-${attribute}]`).forEach(node => {
        node.setAttribute(attribute === 'aria' ? 'aria-label' : 'alt', node.getAttribute(`data-${language}-${attribute}`));
      });
    }
    languageButton.textContent = t('English', '简体中文');
    languageButton.setAttribute('aria-label', t('Switch to English', '切换到简体中文'));
    document.title = t('Grove — 多仓库，一处看清', 'Grove — Many repos. One clear view.');
    document.querySelector('meta[name="description"]').content = t('Grove 是原生 macOS Git 客户端：在一个工程中看清多仓库改动，用工作树组一起浏览同一项工作的 checkout。', 'Grove is a native macOS Git client for multi-repository projects. Bring related checkouts together with worktree groups.');
    document.querySelector('#copy-status').textContent = '';
    updateGroup();
    try { localStorage.setItem('grove-site-language', language); } catch { /* Storage is optional. */ }
  }
  languageButton.addEventListener('click', () => setLanguage(language === 'zh' ? 'en' : 'zh'));
  groupButtons.forEach(button => button.addEventListener('click', () => {
    group = button.dataset.group;
    updateGroup();
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
      document.querySelectorAll('.checkout-row').forEach((node, i) => node.animate([{opacity:.5,transform:'translateY(6px)'},{opacity:1,transform:'none'}], {duration:250,delay:i*45,easing:'ease-out'}));
    }
  }));
  document.querySelector('#copy').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText('zsh scripts/build-app.sh\nopen dist/Grove.app');
      document.querySelector('#copy-status').textContent = t('已复制构建命令。', 'Build commands copied.');
    } catch {
      const code = document.querySelector('pre code');
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges(); selection.addRange(range);
      document.querySelector('#copy-status').textContent = t('命令已选中，请按 ⌘C / Ctrl+C 复制。', 'Commands selected. Press ⌘C / Ctrl+C to copy.');
    }
  });
  const repository = window.GROVE_SITE?.repositoryURL;
  if (repository && /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?$/.test(repository)) {
    document.querySelectorAll('.repository-link').forEach(link => {
      link.href = repository.replace(/\/$/, '') + (link.dataset.repositoryPath ? '/' + link.dataset.repositoryPath : '');
      link.hidden = false;
    });
  }
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      if (entry.isIntersecting) { entry.target.classList.add('in-view'); observer.unobserve(entry.target); }
    }), {threshold:.08});
    document.querySelectorAll('.reveal').forEach(node => observer.observe(node));
  }
  let saved;
  try { saved = localStorage.getItem('grove-site-language'); } catch { /* Keep readable default. */ }
  setLanguage(saved === 'en' ? 'en' : 'zh');
})();
