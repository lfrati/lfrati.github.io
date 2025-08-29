(() => {
  // <stdin>
  document.addEventListener("DOMContentLoaded", function() {
    const codeBlocks = document.querySelectorAll(".highlight");
    codeBlocks.forEach(function(block) {
      const copyButton = document.createElement("button");
      copyButton.className = "copy-button";
      copyButton.textContent = "Copy";
      copyButton.setAttribute("aria-label", "Copy code to clipboard");
      block.appendChild(copyButton);
      copyButton.addEventListener("click", async function() {
        const codeElement = block.querySelector("pre code") || block.querySelector("code");
        let codeText = "";
        if (codeElement) {
          const clonedCode = codeElement.cloneNode(true);
          const lineNumberSpans = clonedCode.querySelectorAll('span[style*="user-select:none"]');
          lineNumberSpans.forEach((span) => span.remove());
          codeText = clonedCode.textContent || "";
        }
        try {
          await navigator.clipboard.writeText(codeText);
          copyButton.textContent = "Copied!";
          copyButton.classList.add("copied");
          setTimeout(function() {
            copyButton.textContent = "Copy";
            copyButton.classList.remove("copied");
          }, 2e3);
        } catch (err) {
          console.error("Failed to copy: ", err);
          copyButton.textContent = "Failed";
          setTimeout(function() {
            copyButton.textContent = "Copy";
          }, 2e3);
        }
      });
    });
  });
  window.resizeSketch = function resizeSketch(obj) {
    try {
      const cnv = obj?.contentWindow?.document?.body?.querySelector("#defaultCanvas0");
      if (!cnv) {
        return;
      }
      obj.style.height = cnv.style.height;
      obj.style.width = cnv.style.width;
    } catch (e) {
    }
  };
})();
