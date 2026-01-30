setTimeout(function () { location.reload(1); }, 20000)

// Measure client-side rendering performance using the Performance API
window.addEventListener('load', function () {
    var perf = window.performance;
    if (!perf || !perf.timing) return;

    var t = perf.timing;

    // Time from navigation start to DOM content loaded
    var domReady = t.domContentLoadedEventEnd - t.navigationStart;
    // Time from navigation start to full page load
    var pageLoad = t.loadEventEnd - t.navigationStart;
    // Time to first byte (network + server processing)
    var ttfb = t.responseStart - t.navigationStart;

    var elDom = document.getElementById('kpi-dom-ready');
    var elLoad = document.getElementById('kpi-page-load');
    var elTtfb = document.getElementById('kpi-ttfb');

    if (elDom) elDom.textContent = domReady + ' ms';
    if (elLoad) elLoad.textContent = pageLoad + ' ms';
    if (elTtfb) elTtfb.textContent = ttfb + ' ms';

    // Color the values based on thresholds
    [
        { el: elDom, val: domReady, good: 500, ok: 1500 },
        { el: elLoad, val: pageLoad, good: 1000, ok: 3000 },
        { el: elTtfb, val: ttfb, good: 200, ok: 600 }
    ].forEach(function (item) {
        if (!item.el) return;
        if (item.val <= item.good) {
            item.el.classList.add('kpi-good');
        } else if (item.val <= item.ok) {
            item.el.classList.add('kpi-ok');
        } else {
            item.el.classList.add('kpi-bad');
        }
    });
});
