(function () {
  "use strict";

  const initializedKey = "__quartoGlossaryBalloonInitialized";
  if (window[initializedKey]) {
    return;
  }
  window[initializedKey] = true;

  const selector = ".glossary-balloon[data-glossary-definition]";
  const popupId = "glossary-balloon-popup";
  const viewportMargin = 8;
  const targetGap = 10;
  const hideDelay = 150;
  let activeTarget = null;
  let popup = null;
  let positionFrame = null;
  let hideTimer = null;

  function ensurePopup() {
    if (popup) {
      return popup;
    }
    popup = document.createElement("div");
    popup.id = popupId;
    popup.className = "glossary-balloon-popup";
    popup.setAttribute("role", "tooltip");
    popup.hidden = true;
    // Readers can move onto the balloon to select or copy its text.
    popup.addEventListener("mouseenter", cancelHide);
    popup.addEventListener("mouseleave", function () {
      scheduleHide(activeTarget);
    });
    document.body.appendChild(popup);
    return popup;
  }

  function cancelHide() {
    if (hideTimer !== null) {
      window.clearTimeout(hideTimer);
      hideTimer = null;
    }
  }

  function scheduleHide(target) {
    cancelHide();
    hideTimer = window.setTimeout(function () {
      hideTimer = null;
      if (activeTarget === target && document.activeElement !== target &&
          !(popup && popup.matches(":hover"))) {
        hide(target);
      }
    }, hideDelay);
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

    const arrowX = targetRect.left + targetRect.width / 2 - left;
    const arrowLimit = 14;
    popup.style.setProperty("--glossary-arrow-x", `${Math.round(
      Math.min(Math.max(arrowX, arrowLimit), popupRect.width - arrowLimit))}px`);
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
    cancelHide();
    if (activeTarget && activeTarget !== target) {
      activeTarget.removeAttribute("aria-describedby");
    }
    activeTarget = target;
    const element = ensurePopup();
    element.textContent = definition;
    element.style.visibility = "hidden";
    element.hidden = false;
    target.setAttribute("aria-describedby", popupId);
    schedulePosition();
  }

  function hide(target) {
    if (target && target !== activeTarget) {
      return;
    }
    cancelHide();
    if (activeTarget) {
      activeTarget.removeAttribute("aria-describedby");
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
      scheduleHide(target);
    });

    // On touch screens there is no hover: the first tap on a term shows its
    // balloon, a second tap follows the link, and a tap elsewhere closes it.
    // A tap also fires mouseover and focus before the click, so whether the
    // balloon was already open is read when the finger goes down.
    let openBeforeTap = false;
    let tapped = false;
    document.addEventListener("pointerdown", function (event) {
      const target = glossaryTarget(event);
      tapped = event.pointerType !== "mouse";
      openBeforeTap = Boolean(target && target === activeTarget &&
        popup && !popup.hidden);
    }, true);
    document.addEventListener("click", function (event) {
      const target = glossaryTarget(event);
      if (!target) {
        if (activeTarget && !(popup && popup.contains(event.target))) {
          hide();
        }
        return;
      }
      if (!target.matches("a") || (tapped && !openBeforeTap)) {
        event.preventDefault();
        show(target);
      }
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
        return;
      }
      // A term without a link opens its balloon like a button.
      const target = glossaryTarget(event);
      if (target && !target.matches("a") &&
          (event.key === "Enter" || event.key === " ")) {
        event.preventDefault();
        show(target);
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
