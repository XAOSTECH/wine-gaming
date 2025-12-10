/**
 * Wine Launcher UI - Frontend JavaScript
 * Safe command execution and real-time output updates
 */

// Update server status and time continuously
setInterval(() => {
    // Update time
    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    document.getElementById('current-time').textContent = timeStr;

    // Check server health
    fetch('/api/health')
        .then(r => r.json())
        .then(data => {
            document.getElementById('server-status').textContent = '✅ Online';
        })
        .catch(() => {
            document.getElementById('server-status').textContent = '❌ Offline';
        });
}, 1000);

/**
 * Run a command safely via whitelist
 */
async function runCommand(action) {
    const btn = event.target;
    const outputEl = document.getElementById('output');
    const timestampEl = document.getElementById('output-timestamp');
    
    // Disable button during execution
    btn.disabled = true;
    btn.textContent = '⏳ Running...';
    
    try {
        outputEl.textContent = `Executing: ${action}...`;
        
        const response = await fetch('/api/run', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ action })
        });

        const data = await response.json();

        if (response.ok) {
            // Display output
            let output = `[${new Date().toLocaleTimeString()}] ${action}\n`;
            output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
            output += data.output || '(no output)';
            
            if (data.error && data.error.trim()) {
                output += '\n\nErrors/Warnings:\n';
                output += data.error;
            }
            
            outputEl.textContent = output;
            
            if (data.success) {
                outputEl.style.borderColor = '#4caf50';
            } else {
                outputEl.style.borderColor = '#f44336';
            }
        } else {
            outputEl.textContent = `Error: ${data.error}\n\nAllowed commands:\n${data.available.join('\n')}`;
            outputEl.style.borderColor = '#f44336';
        }

        timestampEl.textContent = `Last executed: ${new Date().toLocaleTimeString()}`;

    } catch (err) {
        outputEl.textContent = `Connection error: ${err.message}\n\nMake sure Node.js server is running:\n  npm start`;
        outputEl.style.borderColor = '#f44336';
    } finally {
        // Re-enable button
        btn.disabled = false;
        btn.textContent = btn.textContent.replace('⏳ Running...', btn.textContent.split(' ')[0] + ' ' + (btn.textContent.split(' ').slice(1).join(' ') || 'Run'));
        
        // Restore original text
        setTimeout(() => {
            btn.textContent = btn.getAttribute('data-original') || btn.textContent;
        }, 500);
    }
}

/**
 * Clear output panel
 */
function clearOutput() {
    document.getElementById('output').textContent = 'Output cleared.';
    document.getElementById('output-timestamp').textContent = '';
    document.getElementById('output').style.borderColor = '#ccc';
}

/**
 * Copy output to clipboard
 */
function copyOutput() {
    const output = document.getElementById('output').textContent;
    navigator.clipboard.writeText(output).then(() => {
        alert('Output copied to clipboard!');
    }).catch(() => {
        alert('Failed to copy (clipboard access denied)');
    });
}

// Store original button text
document.querySelectorAll('.btn').forEach(btn => {
    btn.setAttribute('data-original', btn.textContent);
});

// Initial output message
window.addEventListener('load', () => {
    const output = document.getElementById('output');
    output.textContent = `🎮 Wine Launcher Control Panel

Ready to execute commands. Click a button to start.

Available actions:
  • Check Status      → List installed launchers
  • Show Installers   → Find installers in ./installers/
  • Quick Setup       → Reinit + install missing
  • Full Setup        → Fresh install (purge all)
  • Launch [App]      → Start launcher
  • Unmount Z:        → Hide /mnt (fix disk space)
  • Mount Z:          → Restore /mnt
  • Suppress Warnings → Mute Z: errors

Tips:
  • Long operations may take several minutes
  • Check output panel for results
  • Use "Unmount Z:" before EA Desktop disk checks
  • Use "Quick Setup" to preserve installed apps`;
});
