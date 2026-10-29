(function () {
  "use strict";

  const initializedKey = "__quartoGlossaryBalloonInitialized";
  if (window[initializedKey]) {
    return;
  }
  window[initializedKey] = true;

  const selector = ".glossary-balloon[data-glossary-definition]";
  const viewportMargin = 8;
  const targetGap = 7;
  let activeTarget = null;
  let popup = null;
  let positionFrame = null;

  function ensurePopup() {
    if (popup) {
      return popup;
    }
    popup = document.createElement("div");
    popup.className = "glossary-balloon-popup";
    popup.setAttribute("role", "tooltip");
    popup.setAttribute("aria-hidden", "true");
    popup.hidden = true;
    document.body.appendChild(popup);
    return popup;
  }

  function positionPopup() {
    positionFrame = null;
    if (!activeTarget || !popup || popup.hidden) {
      return;
    }
    if (!activeTarget.isConnected) {
      hide();
      return;
    }

    const targetRect = activeTarget.getBoundingClientRect();
    if (targetRect.bottom < viewportMargin ||
        targetRect.top > window.innerHeight - viewportMargin ||
        targetRect.right < viewportMargin ||
        targetRect.left > window.innerWidth - viewportMargin) {
      hide(activeTarget);
      return;
    }
    const popupRect = popup.getBoundingClientRect();
    const maximumLeft = Math.max(
      viewportMargin,
      window.innerWidth - popupRect.width - viewportMargin
    );
    let left = targetRect.left + targetRect.width / 2 - popupRect.width / 2;
    left = Math.min(Math.max(left, viewportMargin), maximumLeft);

    let top = targetRect.top - popupRect.height - targetGap;
    let placement = "above";
    if (top < viewportMargin) {
      top = targetRect.bottom + targetGap;
      placement = "below";
    }
    top = Math.min(
      Math.max(top, viewportMargin),
      Math.max(viewportMargin, window.innerHeight - popupRect.height - viewportMargin)
    );

    popup.dataset.placement = placement;
    popup.style.left = `${Math.round(left)}px`;
    popup.style.top = `${Math.round(top)}px`;
    popup.style.visibility = "visible";
  }

  function schedulePosition() {
    if (!activeTarget || !popup || popup.hidden || positionFrame !== null) {
      return;
    }
    positionFrame = window.requestAnimationFrame(positionPopup);
  }

  function show(target) {
    const definition = target.getAttribute("data-glossary-definition");
    if (!definition) {
      return;
    }
    activeTarget = target;
    const element = ensurePopup();
    element.textContent = definition;
    element.style.visibility = "hidden";
    element.hidden = false;
    schedulePosition();
  }

  function hide(target) {
    if (target && target !== activeTarget) {
      return;
    }
    activeTarget = null;
    if (popup) {
      popup.hidden = true;
      popup.style.visibility = "hidden";
    }
  }

  function glossaryTarget(event) {
    return event.target instanceof Element
      ? event.target.closest(selector)
      : null;
  }

  function initialize() {
    document.addEventListener("mouseover", function (event) {
      const target = glossaryTarget(event);
      if (!target || (event.relatedTarget instanceof Node &&
          target.contains(event.relatedTarget))) {
        return;
      }
      show(target);
    });

    document.addEventListener("mouseout", function (event) {
      const target = glossaryTarget(event);
      if (!target || (event.relatedTarget instanceof Node &&
          target.contains(event.relatedTarget))) {
        return;
      }
      window.setTimeout(function () {
        if (activeTarget === target && document.activeElement !== target) {
          hide(target);
        }
      }, 0);
    });

    document.addEventListener("focusin", function (event) {
      const target = glossaryTarget(event);
      if (target) {
        show(target);
      }
    });

    document.addEventListener("focusout", function (event) {
      const target = glossaryTarget(event);
      if (!target) {
        return;
      }
      window.setTimeout(function () {
        if (activeTarget === target && !target.matches(":hover")) {
          hide(target);
        }
      }, 0);
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        hide();
      }
    });
    document.addEventListener("scroll", schedulePosition, true);
    window.addEventListener("resize", schedulePosition);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, {once: true});
  } else {
    initialize();
  }
})();
