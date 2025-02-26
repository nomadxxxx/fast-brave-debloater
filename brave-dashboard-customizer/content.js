// Apply saved settings on page load
(function() {
  chrome.storage.local.get(['bgType', 'bgColor', 'bgImage'], function(result) {
    if (result.bgType === 'color' && result.bgColor) {
      applyColorBackground(result.bgColor);
    } else if (result.bgType === 'image' && result.bgImage) {
      applyImageBackground(result.bgImage);
    } else {
      // Default to black background if no settings saved
      applyColorBackground('#000000');
    }
  });
  
  function applyColorBackground(color) {
    const elements = document.querySelectorAll('.ntp-contents, body, #root');
    elements.forEach(el => {
      el.style.background = color;
      el.style.backgroundImage = 'none';
    });
    
    // Also target potential background containers
    const bgContainers = document.querySelectorAll('[class*="background"], [id*="background"]');
    bgContainers.forEach(el => {
      el.style.background = color;
      el.style.backgroundImage = 'none';
    });
  }
  
  function applyImageBackground(imageData) {
    const elements = document.querySelectorAll('.ntp-contents, body, #root');
    elements.forEach(el => {
      el.style.backgroundImage = `url(${imageData})`;
      el.style.backgroundSize = 'cover';
      el.style.backgroundPosition = 'center';
      el.style.backgroundRepeat = 'no-repeat';
    });
    
    // Also target potential background containers
    const bgContainers = document.querySelectorAll('[class*="background"], [id*="background"]');
    bgContainers.forEach(el => {
      el.style.backgroundImage = `url(${imageData})`;
      el.style.backgroundSize = 'cover';
      el.style.backgroundPosition = 'center';
      el.style.backgroundRepeat = 'no-repeat';
    });
  }
})();
