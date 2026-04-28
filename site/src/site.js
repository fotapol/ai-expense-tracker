(function () {
  const storageKey = "site-theme";

  function siteConfig() {
    const config = window.__SITE_CONFIG__ || {};
    return {
      appWebsiteUrl: config.appWebsiteUrl || "/",
      privacyUrl: config.privacyUrl || "/privacy",
      termsUrl: config.termsUrl || "/terms",
      supportEmail: config.supportEmail || "",
      supportSubject: config.supportSubject || "",
    };
  }

  function currentTheme() {
    return document.documentElement.dataset.theme === "dark" ? "dark" : "light";
  }

  function applyTheme(theme, persist) {
    document.documentElement.dataset.theme = theme;
    if (persist) {
      try {
        localStorage.setItem(storageKey, theme);
      } catch (_) {
        // Ignore storage errors.
      }
    }

    const toggle = document.querySelector("[data-theme-toggle]");
    if (toggle) {
      toggle.textContent = "Theme: " + (theme === "dark" ? "Dark" : "Light");
      toggle.setAttribute("aria-label", "Switch theme. Current theme: " + theme + ".");
    }
  }

  function fillAnchor(selector, href) {
    document.querySelectorAll(selector).forEach(function (anchor) {
      anchor.setAttribute("href", href);
    });
  }

  function mailtoHref(email, subject) {
    if (!subject) {
      return "mailto:" + email;
    }
    return "mailto:" + email + "?subject=" + encodeURIComponent(subject);
  }

  function hydrateSupport(config) {
    const email = config.supportEmail;
    document.querySelectorAll("[data-support-email-link]").forEach(function (anchor) {
      if (!email) {
        anchor.hidden = true;
        return;
      }
      anchor.textContent = email;
      anchor.setAttribute("href", mailtoHref(email, config.supportSubject));
      anchor.hidden = false;
    });

    document.querySelectorAll("[data-support-line]").forEach(function (node) {
      node.hidden = !email;
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    const config = siteConfig();

    fillAnchor("[data-home-link]", config.appWebsiteUrl);
    fillAnchor("[data-privacy-link]", config.privacyUrl);
    fillAnchor("[data-terms-link]", config.termsUrl);
    hydrateSupport(config);

    const toggle = document.querySelector("[data-theme-toggle]");
    if (toggle) {
      applyTheme(currentTheme(), false);
      toggle.addEventListener("click", function () {
        applyTheme(currentTheme() === "dark" ? "light" : "dark", true);
      });
    }
  });
})();
