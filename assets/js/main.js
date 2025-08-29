// Copy to clipboard functionality for code blocks
document.addEventListener('DOMContentLoaded', function() {
  // Find all code blocks
  const codeBlocks = document.querySelectorAll('.highlight');
  
  codeBlocks.forEach(function(block) {
    // Create copy button
    const copyButton = document.createElement('button');
    copyButton.className = 'copy-button';
    copyButton.textContent = 'Copy';
    copyButton.setAttribute('aria-label', 'Copy code to clipboard');
    
    // Add button to the code block
    block.appendChild(copyButton);
    
    // Handle click event
    copyButton.addEventListener('click', async function() {
      // Get the code content
      const codeElement = block.querySelector('pre code') || block.querySelector('code');
      let codeText = '';
      
      if (codeElement) {
        // Clone the code element to avoid modifying the original
        const clonedCode = codeElement.cloneNode(true);
        
        // Remove line number spans (they have user-select:none style)
        const lineNumberSpans = clonedCode.querySelectorAll('span[style*="user-select:none"]');
        lineNumberSpans.forEach(span => span.remove());
        
        // Get the text content without line numbers
        codeText = clonedCode.textContent || '';
      }
      
      try {
        // Copy to clipboard
        await navigator.clipboard.writeText(codeText);
        
        // Update button state
        copyButton.textContent = 'Copied!';
        copyButton.classList.add('copied');
        
        // Reset button after 2 seconds
        setTimeout(function() {
          copyButton.textContent = 'Copy';
          copyButton.classList.remove('copied');
        }, 2000);
        
      } catch (err) {
        // Clipboard API not available or blocked; avoid deprecated execCommand
        console.error('Failed to copy: ', err);
        copyButton.textContent = 'Failed';
        setTimeout(function() {
          copyButton.textContent = 'Copy';
        }, 2000);
      }
    });
  });
});

// Expose resizeIframe globally so shortcodes can call it via onload
window.resizeSketch = function resizeSketch(obj) {
  try {
    const cnv = obj?.contentWindow?.document?.body?.querySelector('#defaultCanvas0');
    if (!cnv) {
      return;
    }
    obj.style.height = cnv.style.height;
    obj.style.width = cnv.style.width;
  } catch (e) {
    // Silently ignore cross-origin or timing issues
  }
};

