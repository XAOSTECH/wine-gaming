# Installers Directory

Place downloaded game launcher installers here.

**Never commit .exe/.msi files to Git** (see ../.gitignore)

## How to Use

### Option A: Automatic Download
```bash
cd ..
./setup install <app-key>
```

### Option B: Manual Download
1. Download installer from INSTALLER_LINKS.md
2. Save to this directory
3. Run: `../setup install <app-key>`

Example:
```bash
# Download GOG Galaxy
wget https://cdn.gog.com/Open/GOG%20Galaxy/GOG_Galaxy_2.0.exe

# Install
../setup install gog-galaxy
```

## Available Installers

See `../INSTALLER_LINKS.md` for download URLs.
