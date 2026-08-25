(function () {
  "use strict";

  var root = document.documentElement;
  var themeButton = document.getElementById("theme-toggle");
  var savedTheme = null;
  try { savedTheme = localStorage.getItem("wud-theme"); } catch (_) { }
  if (savedTheme === "dark" || savedTheme === "light") root.dataset.theme = savedTheme;
  else if (window.matchMedia) root.dataset.theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

  if (themeButton) {
    themeButton.addEventListener("click", function () {
      var next = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try { localStorage.setItem("wud-theme", next); } catch (_) { }
      themeButton.setAttribute("aria-label", "Use " + (next === "dark" ? "light" : "dark") + " theme");
    });
  }

  var printButton = document.getElementById("print-report");
  if (printButton) printButton.addEventListener("click", function () { window.print(); });

  Array.prototype.forEach.call(document.querySelectorAll(".copy-inline"), function (button) {
    button.addEventListener("click", function () {
      var target = document.getElementById(button.getAttribute("data-copy-target"));
      if (!target) return;
      var text = target.textContent || "";
      var done = function () {
        var old = button.textContent;
        button.textContent = "Copied";
        setTimeout(function () { button.textContent = old; }, 1200);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done);
      else {
        var area = document.createElement("textarea");
        area.value = text;
        document.body.appendChild(area);
        area.select();
        document.execCommand("copy");
        area.remove();
        done();
      }
    });
  });

  var search = document.getElementById("finding-search");
  var severity = document.getElementById("severity-filter");
  var status = document.getElementById("status-filter");
  var category = document.getElementById("category-filter");
  var rows = Array.prototype.slice.call(document.querySelectorAll("#finding-table tbody tr"));
  var cards = Array.prototype.slice.call(document.querySelectorAll(".finding-card"));

  function applyFilters() {
    var query = search ? search.value.toLowerCase().trim() : "";
    var sev = severity ? severity.value.toLowerCase() : "";
    var findingStatus = status ? status.value.toLowerCase() : "";
    var cat = category ? category.value.toLowerCase() : "";
    function visible(node) {
      var text = (node.textContent || "").toLowerCase();
      return (!query || text.indexOf(query) >= 0) &&
        (!sev || (node.dataset.severity || "") === sev) &&
        (!findingStatus || (node.dataset.status || "") === findingStatus) &&
        (!cat || (node.dataset.category || "") === cat);
    }
    rows.forEach(function (row) { row.classList.toggle("hidden", !visible(row)); });
    cards.forEach(function (card) { card.classList.toggle("hidden", !visible(card)); });
  }
  [search, severity, status, category].forEach(function (control) {
    if (control) control.addEventListener(control.tagName === "INPUT" ? "input" : "change", applyFilters);
  });

  Array.prototype.forEach.call(document.querySelectorAll("th[data-sort]"), function (header) {
    header.tabIndex = 0;
    header.setAttribute("role", "button");
    header.setAttribute("aria-sort", "none");
    header.addEventListener("click", function () {
      var table = header.closest("table");
      var body = table.querySelector("tbody");
      var index = Array.prototype.indexOf.call(header.parentNode.children, header);
      var direction = header.dataset.direction === "asc" ? "desc" : "asc";
      header.dataset.direction = direction;
      Array.prototype.forEach.call(header.parentNode.querySelectorAll("th[data-sort]"), function (item) {
        item.setAttribute("aria-sort", item === header ? (direction === "asc" ? "ascending" : "descending") : "none");
      });
      var sorted = Array.prototype.slice.call(body.rows).sort(function (a, b) {
        var left = (a.cells[index].textContent || "").trim().toLowerCase();
        var right = (b.cells[index].textContent || "").trim().toLowerCase();
        var result = left.localeCompare(right, undefined, { numeric: true });
        return direction === "asc" ? result : -result;
      });
      sorted.forEach(function (row) { body.appendChild(row); });
    });
    header.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); header.click(); }
    });
  });
})();
