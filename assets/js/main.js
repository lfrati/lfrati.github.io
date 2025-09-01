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

// ========== TABLE OF CONTENTS FUNCTIONALITY ==========
document.addEventListener('DOMContentLoaded', function() {
  // Get all H1 sections for TOC (main sections in the content)
  const sections = document.querySelectorAll('.post h1[id]');
  const tocButton = document.getElementById('tocButton');
  const tocLines = document.getElementById('tocLines');
  const tocPane = document.getElementById('tocPane');
  const tocItems = document.getElementById('tocItems');
  
  // Only initialize TOC if we have sections and the required elements
  if (sections.length === 0 || !tocButton || !tocLines || !tocPane || !tocItems) {
    return;
  }
  
  let currentSection = -1; // Initialize to -1 so first section can be properly highlighted
  let isPaneOpen = false;
  let isScrolling = false;

  // Generate TOC lines and navigation items
  sections.forEach((section, index) => {
    // Create visual line for each section
    const line = document.createElement('div');
    line.className = 'line';
    tocLines.appendChild(line);

    // Create clickable TOC item
    const item = document.createElement('a');
    item.className = 'toc-item';
    item.href = '#' + section.id;
    item.textContent = section.textContent;
    
    // Handle section navigation
    item.addEventListener('click', function(e) {
      e.preventDefault();
      isScrolling = true;
      
      // Immediately update to clicked section
      updateActiveIndex(index);
      
      // Smooth scroll to section with offset for header
      const offsetTop = section.getBoundingClientRect().top + window.pageYOffset - 80;
      window.scrollTo({
        top: offsetTop,
        behavior: 'smooth'
      });
      
      // Close TOC pane
      closeTocPane();
      
      // Reset scrolling flag after animation and ensure we're still on correct section
      setTimeout(() => {
        isScrolling = false;
        updateActiveSection(); // Double check the active section after scroll completes
      }, 800);
    });
    
    tocItems.appendChild(item);
  });

  // Initialize active section after a short delay to ensure proper layout
  setTimeout(() => {
    updateActiveSection();
  }, 100);
  
  // Also update immediately in case the delay isn't needed
  updateActiveSection();

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

  // Update active section while scrolling (throttled)
  let scrollTimeout;
  window.addEventListener('scroll', function() {
    if (isScrolling) return; // Don't update during programmatic scrolling
    
    clearTimeout(scrollTimeout);
    scrollTimeout = setTimeout(updateActiveSection, 10); // Faster response
  });

  // Also update on resize in case layout changes
  window.addEventListener('resize', function() {
    clearTimeout(scrollTimeout);
    scrollTimeout = setTimeout(updateActiveSection, 100);
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

  // Robust section highlighting logic
  function updateActiveSection() {
    const scrollPos = window.scrollY;
    const windowHeight = window.innerHeight;
    const documentHeight = document.documentElement.scrollHeight;
    
    // Offset for header and better UX (sections become active slightly before reaching top)
    const offset = 120;
    
    // Special case: if we're near the bottom, highlight last section
    if (scrollPos + windowHeight >= documentHeight - 200) {
      updateActiveIndex(sections.length - 1);
      return;
    }
    
    // Find the current active section based on scroll position
    let newActiveSection = 0;
    
    // Go through sections from last to first to find the current one
    for (let i = sections.length - 1; i >= 0; i--) {
      const section = sections[i];
      const rect = section.getBoundingClientRect();
      const sectionTop = rect.top + scrollPos;
      
      // If section top has passed the offset line, this section is active
      if (scrollPos + offset >= sectionTop) {
        newActiveSection = i;
        break;
      }
    }
    
    // Special case: if no section has passed the offset, but we have scroll, 
    // check if the first section is visible and use it
    if (newActiveSection === 0 && sections.length > 0) {
      const firstSection = sections[0];
      const firstRect = firstSection.getBoundingClientRect();
      const firstSectionTop = firstRect.top + scrollPos;
      
      // If we haven't scrolled past the first section by much, keep it active
      if (scrollPos + offset < firstSectionTop + 300) {
        newActiveSection = 0;
      }
    }
    
    updateActiveIndex(newActiveSection);
  }

  // Helper function to update active states
  function updateActiveIndex(newIndex) {
    if (newIndex !== currentSection) {
      currentSection = newIndex;
      
      // Update line indicators
      document.querySelectorAll('.line').forEach((line, index) => {
        line.classList.toggle('active', index === currentSection);
      });
      
      // Update pane items
      document.querySelectorAll('.toc-item').forEach((item, index) => {
        item.classList.toggle('active', index === currentSection);
      });
    }   
  }
});

