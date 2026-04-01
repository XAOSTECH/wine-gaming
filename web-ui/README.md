# Wine Launcher Web UI

Optional browser-based control panel for the Wine Launcher setup script.

## Quick Start

### Prerequisites
- Node.js 14+ and npm

### Installation
```bash
cd web-ui
npm install
```

### Run
```bash
npm start
```

Then open: **http://localhost:3000**

## Features

✅ **Visual command interface** - Click buttons instead of CLI  
✅ **Real-time output** - See command results immediately  
✅ **Launcher status** - Check which apps are installed  
✅ **Safe execution** - Commands whitelisted on server side  
✅ **Localhost only** - Bound to 127.0.0.1 for security  

## Available Commands

- **Check Status** - List all launchers and install status
- **Show Installers** - Display available installers in ./installers/
- **Quick Setup** - Reinitialize dependencies + install missing apps
- **Full Setup** - Complete fresh install (purge + init + install all)
- **Launch [App]** - Start a launcher:
  - Launch GOG Galaxy
  - Launch Epic Games
  - Launch EA Desktop
- **Z: Drive Management** - Control /mnt visibility:
  - Unmount Z: (hide /mnt, fixes EA Desktop disk warnings)
  - Mount Z: (restore /mnt access)
  - Suppress Warnings (mute Z: error logs)

## Architecture

```
server.js           → Express.js server
public/
  ├── index.html    → UI layout
  ├── style.css     → Styling
  └── app.js        → Frontend logic
package.json        → Dependencies
```

### Security Model

- **Whitelist validation**: Only ALLOWED_COMMANDS in server.js can be executed
- **No user input**: Commands are fixed buttons, not free-form input
- **Localhost only**: Bound to 127.0.0.1 (not accessible remotely)
- **Timeout protection**: 5-hour limit on long operations (install-all)
- **Error handling**: Proper error responses without shell leakage

## Troubleshooting

### "Server not responding"
```bash
# Make sure Node.js is running
npm start

# Check if port 3000 is available
lsof -i :3000

# Try different port
PORT=3001 npm start
# Then open http://localhost:3001
```

### "Command failed silently"
- Check browser console (F12) for errors
- Check server terminal output
- Verify `./setup` script exists in parent directory
- Ensure Wine prefix is initialised: `../setup init`

### "Output stuck at 'Running...'"
- Long operations (install-all) may take 30+ minutes
- Do not close browser tab
- Check server terminal for actual progress
- Can safely reload browser (command continues server-side)

## Environment Variables

```bash
PORT=3001                    # Change port
NODE_ENV=production          # Production mode
WINE_DIR=/custom/wine/path   # (would need server.js modification)
```

## Performance

- **First load**: ~200ms
- **Command execution**: Varies (list: ~1s, install-all: 30-120 min)
- **Output rendering**: Real-time, streaming updates
- **Memory**: ~50MB Node.js + dependencies

## Future Enhancements

- [ ] WebSocket for streaming output
- [ ] Progress bar for install-all
- [ ] App launcher icons
- [ ] Settings UI
- [ ] Log file viewer
- [ ] Multi-language support

## Licence

MIT - Same as main project
