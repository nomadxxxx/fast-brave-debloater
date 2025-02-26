document.addEventListener('DOMContentLoaded', function() {
  // Load saved settings
  chrome.storage.local.get(['bgType', 'bgColor', 'bgImage'], function(result) {
    if (result.bgType) {
      document.querySelector(`input[name="bgType"][value="${result.bgType}"]`).checked = true;
      
      if (result.bgType === 'color' && result.bgColor) {
        document.getElementById('colorPicker').value = result.bgColor;
      } else if (result.bgType === 'image' && result.bgImage) {
        document.getElementById('imagePreview').src = result.bgImage;
        document.getElementById('imagePreview').style.display = 'block';
        document.getElementById('imageUpload').disabled = false;
      }
    }
  });
  
  // Toggle input fields based on selection
  document.querySelectorAll('input[name="bgType"]').forEach(function(radio) {
    radio.addEventListener('change', function() {
      if (this.value === 'color') {
        document.getElementById('colorPicker').disabled = false;
        document.getElementById('imageUpload').disabled = true;
      } else {
        document.getElementById('colorPicker').disabled = true;
        document.getElementById('imageUpload').disabled = false;
      }
    });
  });
  
  // Handle image upload preview
  document.getElementById('imageUpload').addEventListener('change', function(event) {
    const file = event.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = function(e) {
        document.getElementById('imagePreview').src = e.target.result;
        document.getElementById('imagePreview').style.display = 'block';
      };
      reader.readAsDataURL(file);
    }
  });
  
  // Apply settings button
  document.getElementById('applySettings').addEventListener('click', function() {
    const bgType = document.querySelector('input[name="bgType"]:checked').value;
    let settings = { bgType };
    
    if (bgType === 'color') {
      settings.bgColor = document.getElementById('colorPicker').value;
    } else if (bgType === 'image') {
      const imagePreview = document.getElementById('imagePreview');
      if (imagePreview.src) {
        settings.bgImage = imagePreview.src;
      }
    }
    
    // Save settings
    chrome.storage.local.set(settings, function() {
      // Close popup after saving
      window.close();
    });
  });
  
  // Reset to default black
  document.getElementById('resetDefault').addEventListener('click', function() {
    // Set to black background
    chrome.storage.local.set({
      bgType: 'color',
      bgColor: '#000000'
    }, function() {
      // Reset UI
      document.getElementById('useColor').checked = true;
      document.getElementById('colorPicker').value = '#000000';
      document.getElementById('colorPicker').disabled = false;
      document.getElementById('imageUpload').disabled = true;
      document.getElementById('imagePreview').style.display = 'none';
      
      // Close popup after saving
      window.close();
    });
  });
});
