# Installation Guide

The `mdtosendy.rb` script is designed to be fully portable and can be installed anywhere on your system.

## Quick Installation

Run the automated install script:

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

## Manual Installation

If you prefer to install manually:

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

