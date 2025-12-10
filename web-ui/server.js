#!/usr/bin/env node

/**
 * Wine Launcher UI - Express.js Server
 * Provides safe execution of bash commands for the setup script
 * 
 * Usage:
 *   npm install
 *   npm start
 *   Open http://localhost:3000
 */

const express = require('express');
const { exec } = require('child_process');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// Whitelist of allowed commands (security)
const ALLOWED_COMMANDS = {
  'list': './setup list',
  'status': './setup list',
  'list-installers': './setup list-installers',
  'install-all': './setup install-all',
  'quick': './setup quick',
  'full': './setup full',
  'launch-epic': './setup launch epic-games',
  'launch-gog': './setup launch gog-galaxy',
  'launch-ea': './setup launch ea-desktop',
  'unmount-z': './setup unmount-z',
  'mount-z': './setup mount-z',
  'suppress-warnings': './setup suppress-z-warnings'
};

/**
 * Execute allowed commands safely
 * POST /api/run
 * Body: { action: "list" | "launch-gog" | etc }
 */
app.post('/api/run', (req, res) => {
  const action = req.body.action;
  
  // Validate action is whitelisted
  if (!ALLOWED_COMMANDS[action]) {
    return res.status(403).json({ 
      error: 'Command not allowed',
      available: Object.keys(ALLOWED_COMMANDS)
    });
  }

  const cmd = ALLOWED_COMMANDS[action];
  
  // Execute with timeout (5 hours for install-all)
  exec(cmd, { 
    timeout: 5 * 60 * 60 * 1000,
    shell: '/bin/bash',
    cwd: path.join(__dirname, '..')  // Run from script directory
  }, (err, stdout, stderr) => {
    res.json({ 
      success: !err, 
      action: action,
      output: stdout, 
      error: stderr,
      timestamp: new Date().toISOString()
    });
  });
});

/**
 * Get server status
 */
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: 'Wine Launcher UI running',
    allowed_commands: Object.keys(ALLOWED_COMMANDS),
    timestamp: new Date().toISOString()
  });
});

/**
 * Root route
 */
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: err.message });
});

// Start server
app.listen(PORT, '127.0.0.1', () => {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`Wine Launcher UI`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`🌐 Open: http://localhost:${PORT}`);
  console.log(`🔒 Localhost only (127.0.0.1)`);
  console.log(`\nPress Ctrl+C to stop`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down gracefully...');
  process.exit(0);
});
