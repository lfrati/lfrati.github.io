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

// ========== INITIALIZATION ==========
document.addEventListener('DOMContentLoaded', function() {
  // Copy to clipboard functionality for code blocks
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

  // ========== TABLE OF CONTENTS FUNCTIONALITY ==========
  // Discover ToC elements and derive section IDs from DOM
  const tocButton = document.getElementById('tocButton');
  const tocPane = document.getElementById('tocPane');
  const tocItems = document.querySelectorAll('.toc-item');
  const lines = document.querySelectorAll('.line');
  if (!tocButton || !tocPane || tocItems.length === 0) return; // No ToC on this page

  // Cache arrays for faster access
  const tocItemEls = Array.from(tocItems);
  const lineEls = Array.from(lines);

  const sectionIds = tocItemEls
    .map((item) => item.getAttribute('data-target'))
    .filter((id) => typeof id === 'string' && id.length > 0);
  if (sectionIds.length === 0) return;

  // Cache section elements once
  const sectionEls = sectionIds.map((id) => document.getElementById(id));

  let isPaneOpen = false;

  // Add event listeners to ToC items
  tocItemEls.forEach((item, index) => {
    item.addEventListener('click', function(e) {
      e.preventDefault();

      // Smooth scroll to section with offset for header
      const section = sectionEls[index];
      if (!section) return;
      const sectionRect = section.getBoundingClientRect();
      const h1Offset = sectionRect.height ? sectionRect.height / 3 : 30;
      const offsetTop = sectionRect.top + window.pageYOffset - h1Offset;
      window.scrollTo({
        top: offsetTop,
        behavior: 'smooth'
      });

      // Add highlight animation to target section
      highlightSection(section);

      // Close TOC pane
      closeTocPane();
    });
  });

  // IntersectionObserver-based highlighting observing server-wrapped sections
  const sectionWrappers = Array.from(document.querySelectorAll('.post-content .toc-section'));
  if (sectionWrappers.length === 0) return;

  // Track visibility state of wrappers and toggle active classes accordingly
  const visibleSections = new Set();
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      const attr = entry.target.getAttribute('data-section');
      const index = attr ? parseInt(attr, 10) : NaN;
      if (Number.isNaN(index)) return;
      if (entry.isIntersecting) {
        visibleSections.add(index);
      } else {
        visibleSections.delete(index);
      }
    });

    tocItemEls.forEach((el, idx) => {
      el.classList.toggle('active', visibleSections.has(idx));
    });
    lineEls.forEach((el, idx) => {
      el.classList.toggle('active', visibleSections.has(idx));
    });
  });

  sectionWrappers.forEach((wrapper) => observer.observe(wrapper));

  // Handle direct navigation to fragments and browser navigation (flash target)
  function handleHashNavigation() {
    if (window.location.hash) {
      const targetId = window.location.hash.substring(1);
      const targetSection = document.getElementById(targetId);
      if (targetSection) {
        highlightSection(targetSection);
      }
    }
  }

  // Handle initial hash and hash changes
  handleHashNavigation();
  window.addEventListener('hashchange', handleHashNavigation);

  // IntersectionObserver handles resize/layout changes; no manual recompute needed

  // Toggle TOC pane on button click
  tocButton.addEventListener('click', function(e) {
    e.stopPropagation();
    isPaneOpen ? closeTocPane() : openTocPane();
  });

  // Close pane when clicking outside
  document.addEventListener('click', function(e) {
    if (!tocPane.contains(e.target) && !tocButton.contains(e.target)) {
      closeTocPane();
    }
  });

  // Pane control functions
  function openTocPane() {
    tocPane.classList.add('open');
    isPaneOpen = true;
  }

  function closeTocPane() {
    tocPane.classList.remove('open');
    isPaneOpen = false;
  }

  // Helper function to highlight a section heading
  function highlightSection(sectionElement) {
    if (!sectionElement) return;
    
    // Remove any existing highlight class
    sectionElement.classList.remove('section-highlight');
    
    // Add highlight class with a small delay to trigger animation
    setTimeout(() => {
      sectionElement.classList.add('section-highlight');
      
      // Remove the class after animation completes
      setTimeout(() => {
        sectionElement.classList.remove('section-highlight');
      }, 2000);
    }, 100);
  }
});

// Floating footnotes now handled by Hugo shortcode `fn`; no JS needed

