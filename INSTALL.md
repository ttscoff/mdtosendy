# Installation Guide

The `mdtosendy.rb` script is designed to be fully portable and can be installed anywhere on your system.

## Bootstrap Installation (Recommended)

The easiest way to install mdtosendy is using the bootstrap script:

```bash
curl -s https://github.com/ttscoff/mdtosendy/raw/main/bootstrap.sh | bash
```

This will:
- Prompt for an installation directory (defaults to `~/mdtosendy`)
- Clone the repository from [https://github.com/ttscoff/mdtosendy](https://github.com/ttscoff/mdtosendy)
- Run the installation script automatically
- Link `mdtosendy` to your PATH
- Set up configuration files

The repository will be cloned to your chosen directory, allowing you to easily update it later with `git pull`.

## Updating Your Installation

### Using the Bootstrap Script

If you saved the `bootstrap.sh` script locally, you can update your installation with:

```bash
./bootstrap.sh --update
```

This will:
- Find the installed `mdtosendy` script (following symlinks)
- Navigate to the repository directory
- Run `git pull` to get the latest changes
- Re-run `install.sh` to update the symlink if needed

### Manual Update

You can also update manually:

1. **Find where mdtosendy is installed:**
   ```bash
   # Follow the symlink to find the real location
   dirname $(readlink -f $(which mdtosendy))
   ```

   Or if you know the install directory (default is `~/mdtosendy`):
   ```bash
   cd ~/mdtosendy
   ```

2. **Pull the latest changes:**
   ```bash
   git pull
   ```

3. **Optionally re-run install.sh:**
   ```bash
   ./install.sh
   ```

   This ensures the symlink is up to date and any new template files are copied.

## Manual Installation

If you prefer to install manually or clone the repository yourself:

### Step 1: Clone the Repository

```bash
git clone https://github.com/ttscoff/mdtosendy.git ~/mdtosendy
cd ~/mdtosendy
```

### Step 2: Run the Install Script

```bash
./install.sh
```

The install script will:
- Make the script executable
- Check for required Ruby gems (nokogiri)
- Examine your PATH and suggest the best installation location
- Link the script to your PATH
- Create `~/.config/mdtosendy/` directory
- Copy template and example files
- Provide instructions for completing setup

### Alternative: Copy Script Only

If you prefer to just copy the script without cloning the repository:

1. **Copy the script to your desired location:**
   ```bash
   cp mdtosendy.rb ~/usr/local/bin/mdtosendy
   # or
   cp mdtosendy.rb /usr/local/bin/mdtosendy
   ```

2. **Make it executable:**
   ```bash
   chmod +x ~/usr/local/bin/mdtosendy
   # or
   chmod +x /usr/local/bin/mdtosendy
   ```

3. **Ensure all configuration files are in `~/.config/mdtosendy/`:**
   ```bash
   mkdir -p ~/.config/mdtosendy
   ```

   Required files:
   - `~/.config/mdtosendy/config.yml` - Configuration file
   - `~/.config/mdtosendy/styles.css` - CSS styles
   - `~/.config/mdtosendy/email-template.html` - Email template

4. **Set up your configuration:**
   - Copy `config.example.yml` to `~/.config/mdtosendy/config.yml` and edit with your values
   - Copy `styles.example.css` to `~/.config/mdtosendy/styles.css` and customize
   - Copy `email-template.html` to `~/.config/mdtosendy/email-template.html`

   **Note:** With this method, you won't be able to easily update with `git pull`. Consider using the bootstrap installation method instead.

## Usage

Once installed, you can run the script from any directory:

```bash
# From anywhere on your system
mdtosendy your-email.md

# With preview
mdtosendy --preview your-email.md

# Validate configuration
mdtosendy --validate
```

## File Locations

All configuration and template files are stored in:
- `~/.config/mdtosendy/config.yml`
- `~/.config/mdtosendy/styles.css`
- `~/.config/mdtosendy/email-template.html`

The script itself can be installed anywhere and will automatically find these files in your home directory's config folder.

## Development

For visual CSS editing, use the `email-dev.html` file in the project directory. It links to your CSS file and allows you to see changes in real-time.

