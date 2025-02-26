// Update clock function
function updateClock() {
  const now = new Date();
  
  // Update time
  const hours = now.getHours().toString().padStart(2, '0');
  const minutes = now.getMinutes().toString().padStart(2, '0');
  document.getElementById('clock').textContent = `${hours}:${minutes}`;
  
  // Update date
  const options = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
  document.getElementById('date').textContent = now.toLocaleDateString(undefined, options);
}

// Apply saved background settings
function applyBackgroundSettings() {
  chrome.storage.local.get(['bgType', 'bgColor', 'bgImage'], function(result) {
    if (result.bgType === 'color' && result.bgColor) {
      document.body.style.backgroundImage = 'none';
      document.body.style.backgroundColor = result.bgColor;
    } else if (result.bgType === 'image' && result.bgImage) {
      document.body.style.backgroundImage = `url(${result.bgImage})`;
    } else {
      // Default to black if no settings
      document.body.style.backgroundImage = 'none';
      document.body.style.backgroundColor = '#000000';
    }
  });
}

// Open extension popup when settings icon is clicked
document.getElementById('settings-icon').addEventListener('click', function() {
  chrome.runtime.sendMessage({ action: 'openPopup' });
});

// Listen for storage changes to update background in real-time
chrome.storage.onChanged.addListener(function(changes, namespace) {
  if (namespace === 'local') {
    applyBackgroundSettings();
  }
});

// Initialize
document.addEventListener('DOMContentLoaded', function() {
  updateClock();
  setInterval(updateClock, 1000);
  applyBackgroundSettings();
});
